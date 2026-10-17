//! The asset resolver: turns the texture, mesh, material and font paths a scene names into
//! engine data, and into render service resources.

const std = @import("std");

const c = @import("c.zig").c;
const handles = @import("handle").Handles(c);
const heap = @import("heap");

const E = @import("kerror").Errors(c);

const mesh_shape = @import("mesh_shape.zig");

const res_prefix = "res://";
const primitive_prefix = "res://primitives/";

const path_buf_max = 1024;

/// Allocated by `ke_asset_resolver_create` and freed by `vtDestroy`. `api` is the vtable the handle
/// refers to. The loaders are borrowed and stay null when none was injected, which makes the
/// resolving slots that need them fail. `project_root` is the only memory the state owns, and it is
/// null exactly when no root was given.
///
/// The resolver keeps no asset: decoded textures, baked meshes, parsed materials and baked fonts
/// belong to the caller until handed back to the matching free slot. The plain slots produce data
/// and stop. The "into" slots add a borrowed render service and its cache keyed by the authored
/// path: each asks the service first and returns what it holds without touching a file; on a miss
/// it runs the plain slot, uploads the result under the authored path, and releases the decoded
/// or baked data whatever the upload returns. Every slot rejects a missing resolver, handle or
/// pointer as an invalid argument, and each runs on the thread that calls it.
const State = struct {
    api: c.ke_asset_resolver,
    image_loader: ?*c.ke_image_loader,
    font_loader: ?*c.ke_font_loader,
    project_root: ?[:0]u8,
};

fn stateOf(self: *c.ke_asset_resolver) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// Returns null for a null input and also when the allocation fails, so a caller that needs to tell
/// the two apart must check its own input.
fn dupCStr(s: [*c]const u8) ?[:0]u8 {
    if (s == null) return null;
    return heap.gpa.dupeZ(u8, std.mem.span(s)) catch null;
}

/// Opens the file for binary reading and closes it again, so it reports whether the file can be
/// opened, not whether it holds data.
fn fileExists(path: [*:0]const u8) bool {
    const f = std.c.fopen(path, "rb") orelse return false;
    _ = std.c.fclose(f);
    return true;
}

fn copyStringClamped(dst: []u8, src: []const u8) void {
    if (dst.len == 0) return;
    const n = @min(src.len, dst.len - 1);
    @memcpy(dst[0..n], src[0..n]);
    dst[n] = 0;
}

/// Writes the file path `path` names into `out`, terminated: a path that begins with "res://" is
/// joined to the project root, or stands as its remainder when there is none, and any other path
/// is copied as written. Fails as an invalid argument, leaving `out` unspecified, when the result
/// and its terminator do not fit.
fn resolvePath(s: *const State, path: [*:0]const u8, out: []u8, out_error: [*c][*c]c.ke_error) bool {
    const p = std.mem.span(path);
    const written = if (!std.mem.startsWith(u8, p, res_prefix))
        std.fmt.bufPrintZ(out, "{s}", .{p})
    else if (s.project_root) |root| blk: {
        const remainder = p[res_prefix.len..];
        const sep: []const u8 = if (root.len > 0 and root[root.len - 1] != '/' and root[root.len - 1] != '\\' and
            (remainder.len == 0 or (remainder[0] != '/' and remainder[0] != '\\'))) "/" else "";
        break :blk std.fmt.bufPrintZ(out, "{s}{s}{s}", .{ root, sep, remainder });
    } else std.fmt.bufPrintZ(out, "{s}", .{p[res_prefix.len..]});
    _ = written catch {
        E.fail(out_error, .invalid_argument, "resolved path does not fit", @src());
        return false;
    };
    return true;
}

/// Slot `resolve_path`. Resolves through `resolvePath` into the caller's buffer.
fn vtResolvePath(self_in: ?*c.ke_asset_resolver, path: [*c]const u8, out: [*c]u8, out_size: usize, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or path == null or out == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    return resolvePath(stateOf(self), path, out[0..out_size], out_error);
}

fn tomlNumberIn(tab: ?*c.toml_table_t, key: [*c]const u8) ?f32 {
    const d = c.toml_double_in(tab, key);
    if (d.ok != 0) return @floatCast(d.u.d);
    const i = c.toml_int_in(tab, key);
    if (i.ok != 0) return @floatFromInt(i.u.i);
    return null;
}

fn tomlNumberAt(arr: ?*c.toml_array_t, idx: c_int) ?f32 {
    const d = c.toml_double_at(arr, idx);
    if (d.ok != 0) return @floatCast(d.u.d);
    const i = c.toml_int_at(arr, idx);
    if (i.ok != 0) return @floatFromInt(i.u.i);
    return null;
}

/// The only reader of material files, called by vtResolveMaterial with the path it resolved. Every
/// field it sets is first written with its default, so a key the file leaves out keeps that
/// default. On failure the spec holds only those defaults.
fn parseMaterialFile(path: [*:0]const u8, out: *c.ke_material_spec) error{ NotFound, Malformed }!void {
    out.base_color[0] = 1.0;
    out.base_color[1] = 1.0;
    out.base_color[2] = 1.0;
    out.base_color[3] = 1.0;
    out.metallic = 0.0;
    out.roughness = 0.5;
    out.albedo_path[0] = 0;
    out.normal_path[0] = 0;
    out.alpha_mode = c.KE_ALPHA_MODE_OPAQUE;
    out.alpha_cutoff = 0.5;
    out.ior = 1.5;
    out.distortion_strength = 0.05;

    const fp = std.c.fopen(path, "rb") orelse return error.NotFound;
    var errbuf: [200]u8 = undefined;
    const root = c.toml_parse_file(@ptrCast(@alignCast(fp)), &errbuf, errbuf.len);
    _ = std.c.fclose(fp);
    if (root == null) return error.Malformed;
    defer c.toml_free(root);

    const mat = c.toml_table_in(root, "material") orelse return error.Malformed;

    if (c.toml_array_in(mat, "base_color")) |bc| {
        for (0..4) |i| {
            if (tomlNumberAt(bc, @intCast(i))) |f| out.base_color[i] = f;
        }
    }

    if (tomlNumberIn(mat, "metallic")) |f| out.metallic = f;
    if (tomlNumberIn(mat, "roughness")) |f| out.roughness = f;
    if (tomlNumberIn(mat, "alpha_cutoff")) |f| out.alpha_cutoff = f;
    if (tomlNumberIn(mat, "ior")) |f| out.ior = f;
    if (tomlNumberIn(mat, "distortion_strength")) |f| out.distortion_strength = f;

    const albedo = c.toml_string_in(mat, "albedo");
    if (albedo.ok != 0) {
        copyStringClamped(&out.albedo_path, std.mem.span(albedo.u.s));
        std.c.free(albedo.u.s);
    }
    const normal = c.toml_string_in(mat, "normal");
    if (normal.ok != 0) {
        copyStringClamped(&out.normal_path, std.mem.span(normal.u.s));
        std.c.free(normal.u.s);
    }

    const am = c.toml_string_in(mat, "alpha_mode");
    if (am.ok != 0) {
        const mode = std.mem.span(am.u.s);
        if (std.mem.eql(u8, mode, "MASK")) {
            out.alpha_mode = c.KE_ALPHA_MODE_MASK;
        } else if (std.mem.eql(u8, mode, "BLEND")) {
            out.alpha_mode = c.KE_ALPHA_MODE_BLEND;
        }
        std.c.free(am.u.s);
    }
}

/// Slot `resolve_texture`, and the decode step of `vtResolveTextureInto` on a cache miss. A
/// missing image loader reports an invalid argument and a missing file reports not found, both
/// before the loader is called; a loader failure is reported through the same out-error. Each
/// returns false. On success the decoded data belongs to the caller until `vtFreeTexture`.
fn vtResolveTexture(
    self_in: ?*c.ke_asset_resolver,
    path: [*c]const u8,
    out: [*c]?*c.ke_texture_data,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or path == null or out == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self);
    const loader = s.image_loader orelse {
        E.fail(out_error, .invalid_argument, "no image loader injected", @src());
        return false;
    };

    var buf: [path_buf_max]u8 = undefined;
    if (!resolvePath(s, path, &buf, out_error)) return false;
    const resolved: [*:0]const u8 = @ptrCast(&buf);
    if (!fileExists(resolved)) {
        E.fail(out_error, .not_found, "texture file not found", @src());
        return false;
    }

    out.* = loader.load_image.?(loader, resolved, out_error);
    return out.* != null;
}

/// Slot `free_texture`. Hands the data back to the image loader; does nothing without one.
fn vtFreeTexture(self_in: ?*c.ke_asset_resolver, data: ?*c.ke_texture_data) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or data == null) return;
    const s = stateOf(self);
    if (s.image_loader) |loader| {
        if (loader.free_image) |free_image| free_image(loader, data);
    }
}

/// Slot `resolve_mesh`, and the bake step of `vtResolveMeshInto` on a cache miss. A mesh has no
/// file: only a path under "res://primitives/" naming "quad", "plane", "cube" or "sphere" is
/// accepted, and any other path or name reports not found and returns false. The shape it fills
/// belongs to the caller until `vtFreeMesh` releases it.
fn vtResolveMesh(
    self_in: ?*c.ke_asset_resolver,
    path: [*c]const u8,
    out: ?*c.ke_mesh_shape_data,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or path == null or out == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }

    const p = std.mem.span(path);
    if (std.mem.startsWith(u8, p, primitive_prefix)) {
        const name = p[primitive_prefix.len..];
        const kind: c.ke_mesh_primitive = if (std.mem.eql(u8, name, "quad"))
            c.KE_MESH_PRIMITIVE_QUAD
        else if (std.mem.eql(u8, name, "plane"))
            c.KE_MESH_PRIMITIVE_PLANE
        else if (std.mem.eql(u8, name, "cube"))
            c.KE_MESH_PRIMITIVE_CUBE
        else if (std.mem.eql(u8, name, "sphere"))
            c.KE_MESH_PRIMITIVE_SPHERE
        else {
            E.fail(out_error, .not_found, "unknown primitive", @src());
            return false;
        };
        return mesh_shape.ke_mesh_shape_bake_internal(kind, 0, out);
    }
    E.fail(out_error, .not_found, "mesh not found", @src());
    return false;
}

/// Slot `free_mesh`. Releases the shape filled by `vtResolveMesh`.
fn vtFreeMesh(self_in: ?*c.ke_asset_resolver, data: ?*c.ke_mesh_shape_data) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or data == null) return;
    mesh_shape.ke_mesh_shape_free_internal(data);
}

/// Slot `resolve_material`, and the first step of `vtResolveMaterialInto` on a cache miss. The
/// file is TOML read by `parseMaterialFile`, so a key it omits keeps its default. A file that
/// cannot be opened reports not found, one that is not TOML or has no material table reports io;
/// both return false.
fn vtResolveMaterial(
    self_in: ?*c.ke_asset_resolver,
    path: [*c]const u8,
    out: ?*c.ke_material_spec,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or path == null or out == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self);
    var buf: [path_buf_max]u8 = undefined;
    if (!resolvePath(s, path, &buf, out_error)) return false;
    parseMaterialFile(@ptrCast(&buf), out.?) catch |err| {
        switch (err) {
            error.NotFound => E.fail(out_error, .not_found, "material file not found", @src()),
            error.Malformed => E.fail(out_error, .io, "failed to parse material file", @src()),
        }
        return false;
    };
    return true;
}

/// Slot `resolve_font`. Same order of checks and failures as `vtResolveTexture`, against the font
/// loader. On success the baked font belongs to the caller until `vtFreeFont`.
fn vtResolveFont(
    self_in: ?*c.ke_asset_resolver,
    path: [*c]const u8,
    pixel_size: f32,
    first_codepoint: u32,
    codepoint_count: u32,
    atlas_size: u32,
    out: [*c]?*c.ke_font_data,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or path == null or out == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self);
    const loader = s.font_loader orelse {
        E.fail(out_error, .invalid_argument, "no font loader injected", @src());
        return false;
    };

    var buf: [path_buf_max]u8 = undefined;
    if (!resolvePath(s, path, &buf, out_error)) return false;
    const resolved: [*:0]const u8 = @ptrCast(&buf);
    if (!fileExists(resolved)) {
        E.fail(out_error, .not_found, "font file not found", @src());
        return false;
    }

    out.* = loader.load_font.?(
        loader,
        resolved,
        pixel_size,
        first_codepoint,
        codepoint_count,
        atlas_size,
        out_error,
    );
    return out.* != null;
}

/// Slot `free_font`. Hands the data back to the font loader; does nothing without one.
fn vtFreeFont(self_in: ?*c.ke_asset_resolver, data: ?*c.ke_font_data) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or data == null) return;
    const s = stateOf(self);
    if (s.font_loader) |loader| {
        if (loader.free_font) |free_font| free_font(loader, data);
    }
}

/// Slot `resolve_texture_into`. Checks the service's cache first, so a path it already holds costs
/// no file access. Uploads under the authored path, not the resolved one, so the service keys the
/// texture by what the caller wrote. A missing service is an invalid argument; the failures of
/// `vtResolveTexture` and of the upload are reported as they are. Each returns the none handle.
fn vtResolveTextureInto(
    self_in: ?*c.ke_asset_resolver,
    core_in: ?*c.ke_render_service,
    path: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_texture_handle {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_TEXTURE_NONE;
    };
    const core = core_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_TEXTURE_NONE;
    };
    if (self.handle == null or path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_TEXTURE_NONE;
    }

    var cached: c.ke_texture_handle = undefined;
    if (core.try_get_texture.?(core, path, &cached)) return cached;

    var data: ?*c.ke_texture_data = null;
    if (!vtResolveTexture(self, path, &data, out_error)) return c.KE_TEXTURE_NONE;

    const d = data.?;
    const h = core.upload_texture.?(core, path, d.width, d.height, d.pixels, out_error);
    vtFreeTexture(self, data);
    return h;
}

const gpu_floats_per_vertex = 11;

/// Slot `resolve_mesh_into`. Checks the service's cache first, as `vtResolveTextureInto` does,
/// and uploads the baked vertices converted to the layout the service takes. The shape is freed
/// on every path once it is baked, so none of its memory outlives the call. An allocation failure
/// reports out of memory; the other failures are those of `vtResolveMesh` and of the upload.
/// Each returns the none handle.
fn vtResolveMeshInto(
    self_in: ?*c.ke_asset_resolver,
    core_in: ?*c.ke_render_service,
    path: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_mesh_handle {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_MESH_NONE;
    };
    const core = core_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_MESH_NONE;
    };
    if (self.handle == null or path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_MESH_NONE;
    }

    var cached: c.ke_mesh_handle = undefined;
    if (core.try_get_mesh.?(core, path, &cached)) return cached;

    var shape: c.ke_mesh_shape_data = undefined;
    if (!vtResolveMesh(self, path, &shape, out_error)) return c.KE_MESH_NONE;

    const float_count = @as(usize, shape.vertex_count) * gpu_floats_per_vertex;
    const byte_count = float_count * @sizeOf(f32);
    const gpu_verts = heap.gpa.alloc(f32, float_count) catch {
        vtFreeMesh(self, &shape);
        E.fail(out_error, .out_of_memory, "vertex conversion buffer allocation failed", @src());
        return c.KE_MESH_NONE;
    };

    for (0..shape.vertex_count) |i| {
        const v = &shape.vertices[i];
        const dst = gpu_verts[i * gpu_floats_per_vertex ..][0..gpu_floats_per_vertex];
        dst[0] = v.x;
        dst[1] = v.y;
        dst[2] = v.z;
        dst[3] = v.nx;
        dst[4] = v.ny;
        dst[5] = v.nz;
        dst[6] = v.u;
        dst[7] = v.v;
        dst[8] = v.tx;
        dst[9] = v.ty;
        dst[10] = v.tz;
    }

    const h = core.upload_mesh.?(
        core,
        path,
        gpu_verts.ptr,
        byte_count,
        shape.indices,
        shape.index_count,
        out_error,
    );
    heap.gpa.free(gpu_verts);
    vtFreeMesh(self, &shape);
    return h;
}

/// Slot `resolve_material_into`. Checks the service's cache first. The albedo and normal textures
/// go through `vtResolveTextureInto`, so each is cached under its own path, and a failure there
/// ends the call before the material is created. The other failures are those of
/// `vtResolveMaterial` and of the material creation. Each returns the none handle.
fn vtResolveMaterialInto(
    self_in: ?*c.ke_asset_resolver,
    core_in: ?*c.ke_render_service,
    path: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_material_handle {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_MATERIAL_NONE;
    };
    const core = core_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_MATERIAL_NONE;
    };
    if (self.handle == null or path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_MATERIAL_NONE;
    }

    var cached: c.ke_material_handle = undefined;
    if (core.try_get_material.?(core, path, &cached)) return cached;

    var spec: c.ke_material_spec = undefined;
    if (!vtResolveMaterial(self, path, &spec, out_error)) return c.KE_MATERIAL_NONE;

    var albedo = c.KE_TEXTURE_NONE;
    if (spec.albedo_path[0] != 0) {
        albedo = vtResolveTextureInto(self, core, @ptrCast(&spec.albedo_path), out_error);
        if (albedo.bits == c.KE_HANDLE_NONE) return c.KE_MATERIAL_NONE;
    }
    var normal = c.KE_TEXTURE_NONE;
    if (spec.normal_path[0] != 0) {
        normal = vtResolveTextureInto(self, core, @ptrCast(&spec.normal_path), out_error);
        if (normal.bits == c.KE_HANDLE_NONE) return c.KE_MATERIAL_NONE;
    }

    return core.create_material.?(
        core,
        path,
        &spec.base_color,
        spec.metallic,
        spec.roughness,
        albedo,
        normal,
        spec.alpha_mode,
        spec.alpha_cutoff,
        spec.ior,
        spec.distortion_strength,
        0,
        out_error,
    );
}

/// The destroy of the handle that `ke_asset_resolver_create` returns. Frees the root copy and the
/// state; the loaders are not touched.
fn vtDestroy(self_in: ?*c.ke_asset_resolver) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.project_root) |root| heap.gpa.free(root);
    heap.gpa.destroy(s);
}

/// Factory. The loaders are kept by pointer and never freed, and either may be null, which makes
/// the slots that need it fail; the project root is copied. A failed state allocation or root
/// copy reports out of memory and returns a null handle, the state freed again in the second
/// case.
export fn ke_asset_resolver_create(
    image_loader: ?*c.ke_image_loader,
    font_loader: ?*c.ke_font_loader,
    project_root: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_asset_resolver_handle {
    const null_handle = std.mem.zeroes(c.ke_asset_resolver_handle);

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = std.mem.zeroes(State);

    s.image_loader = image_loader;
    s.font_loader = font_loader;
    s.project_root = dupCStr(project_root);
    if (project_root != null and s.project_root == null) {
        heap.gpa.destroy(s);
        E.fail(out_error, .out_of_memory, "project root allocation failed", @src());
        return null_handle;
    }

    s.api.handle = s;
    s.api.resolve_texture = vtResolveTexture;
    s.api.free_texture = vtFreeTexture;
    s.api.resolve_mesh = vtResolveMesh;
    s.api.free_mesh = vtFreeMesh;
    s.api.resolve_material = vtResolveMaterial;
    s.api.resolve_font = vtResolveFont;
    s.api.free_font = vtFreeFont;
    s.api.resolve_texture_into = vtResolveTextureInto;
    s.api.resolve_mesh_into = vtResolveMeshInto;
    s.api.resolve_material_into = vtResolveMaterialInto;
    s.api.resolve_path = vtResolvePath;

    return .{ .ref = &s.api, .destroy = vtDestroy };
}

const testing = std.testing;

const material_tolerance: f32 = 1e-6;

const MaterialFile = struct {
    tmp: std.testing.TmpDir,
    path: [std.fs.max_path_bytes]u8,

    fn init(contents: []const u8) !MaterialFile {
        var self = MaterialFile{ .tmp = std.testing.tmpDir(.{}), .path = undefined };
        errdefer self.tmp.cleanup();

        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = "probe.material", .data = contents });

        const joined = try std.fmt.bufPrint(
            &self.path,
            ".zig-cache/tmp/{s}/probe.material",
            .{self.tmp.sub_path},
        );
        self.path[joined.len] = 0;
        return self;
    }

    fn cPath(self: *const MaterialFile) [*:0]const u8 {
        return @ptrCast(&self.path);
    }

    fn deinit(self: *MaterialFile) void {
        self.tmp.cleanup();
    }
};

test "a material file that is not there fails instead of yielding a blank material" {
    var spec = std.mem.zeroes(c.ke_material_spec);
    try testing.expectError(error.NotFound, parseMaterialFile("/this/does/not/exist.material", &spec));
}

test "a file without a material section is not a material" {
    var file = try MaterialFile.init("[other_section]\nfoo = 1\n");
    defer file.deinit();

    var spec = std.mem.zeroes(c.ke_material_spec);
    try testing.expectError(error.Malformed, parseMaterialFile(file.cPath(), &spec));
}

test "every authored key reaches the spec it was written for" {
    var file = try MaterialFile.init(
        \\[material]
        \\base_color = [0.8, 0.2, 0.1, 1.0]
        \\metallic   = 0.7
        \\roughness  = 0.25
        \\albedo     = "res://textures/rust.png"
        \\normal     = "res://textures/rust_n.png"
        \\
    );
    defer file.deinit();

    var spec = std.mem.zeroes(c.ke_material_spec);
    try parseMaterialFile(file.cPath(), &spec);

    try testing.expectApproxEqAbs(@as(f32, 0.8), spec.base_color[0], material_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 0.2), spec.base_color[1], material_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 0.1), spec.base_color[2], material_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 1.0), spec.base_color[3], material_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 0.7), spec.metallic, material_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 0.25), spec.roughness, material_tolerance);
    try testing.expectEqualStrings("res://textures/rust.png", std.mem.sliceTo(&spec.albedo_path, 0));
    try testing.expectEqualStrings("res://textures/rust_n.png", std.mem.sliceTo(&spec.normal_path, 0));
}

test "a key the author left out falls back to the default rather than to zero" {
    var file = try MaterialFile.init("[material]\nmetallic = 1.0\n");
    defer file.deinit();

    var spec = std.mem.zeroes(c.ke_material_spec);
    try parseMaterialFile(file.cPath(), &spec);

    try testing.expectApproxEqAbs(@as(f32, 1.0), spec.metallic, material_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 1.0), spec.base_color[0], material_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 1.0), spec.base_color[3], material_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 0.5), spec.roughness, material_tolerance);
    try testing.expectEqualStrings("", std.mem.sliceTo(&spec.albedo_path, 0));
    try testing.expectEqualStrings("", std.mem.sliceTo(&spec.normal_path, 0));
}

const geometry_tolerance: f32 = 1e-5;

var fake_loader_api: c.ke_image_loader = undefined;
var fake_loader_pixels: [16]u8 = undefined;
var fake_loader_texture: c.ke_texture_data = undefined;
var fake_loader_last_path: [std.fs.max_path_bytes]u8 = undefined;
var fake_loader_last_path_len: usize = 0;
var fake_loader_load_count: u32 = 0;
var fake_loader_free_count: u32 = 0;

fn fakeLoadImage(
    self: [*c]c.ke_image_loader,
    path: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) [*c]c.ke_texture_data {
    _ = self;
    _ = out_error;
    const p = std.mem.span(path);
    const n = @min(p.len, fake_loader_last_path.len - 1);
    @memcpy(fake_loader_last_path[0..n], p[0..n]);
    fake_loader_last_path_len = n;
    fake_loader_load_count += 1;

    fake_loader_pixels = std.mem.zeroes([16]u8);
    fake_loader_texture = std.mem.zeroes(c.ke_texture_data);
    fake_loader_texture.width = 2;
    fake_loader_texture.height = 2;
    fake_loader_texture.pixels = &fake_loader_pixels;
    fake_loader_texture.byte_count = fake_loader_pixels.len;
    return &fake_loader_texture;
}

fn fakeFreeImage(self: [*c]c.ke_image_loader, data: [*c]c.ke_texture_data) callconv(.c) void {
    _ = self;
    _ = data;
    fake_loader_free_count += 1;
}

fn resetFakeLoader() *c.ke_image_loader {
    fake_loader_api = std.mem.zeroes(c.ke_image_loader);
    fake_loader_api.handle = &fake_loader_api;
    fake_loader_api.load_image = fakeLoadImage;
    fake_loader_api.free_image = fakeFreeImage;
    fake_loader_last_path_len = 0;
    fake_loader_load_count = 0;
    fake_loader_free_count = 0;
    return &fake_loader_api;
}

fn fakeLoaderLastPath() []const u8 {
    return fake_loader_last_path[0..fake_loader_last_path_len];
}

const TempAsset = struct {
    tmp: std.testing.TmpDir,
    dir_buf: [std.fs.max_path_bytes]u8,
    dir_len: usize,
    path_buf: [std.fs.max_path_bytes]u8,
    path_len: usize,

    fn init(name: []const u8, contents: []const u8) !TempAsset {
        var self = TempAsset{
            .tmp = std.testing.tmpDir(.{}),
            .dir_buf = undefined,
            .dir_len = 0,
            .path_buf = undefined,
            .path_len = 0,
        };
        errdefer self.tmp.cleanup();

        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = name, .data = contents });

        const dir = try std.fmt.bufPrint(&self.dir_buf, ".zig-cache/tmp/{s}", .{self.tmp.sub_path});
        self.dir_len = dir.len;
        self.dir_buf[dir.len] = 0;

        const full = try std.fmt.bufPrint(&self.path_buf, "{s}/{s}", .{ dir, name });
        self.path_len = full.len;
        self.path_buf[full.len] = 0;

        return self;
    }

    fn cPath(self: *const TempAsset) [*:0]const u8 {
        return @ptrCast(&self.path_buf);
    }

    fn fullPath(self: *const TempAsset) []const u8 {
        return self.path_buf[0..self.path_len];
    }

    fn cDir(self: *const TempAsset) [*:0]const u8 {
        return @ptrCast(&self.dir_buf);
    }

    fn deinit(self: *TempAsset) void {
        self.tmp.cleanup();
    }
};

const Resolver = struct {
    handle: c.ke_asset_resolver_handle,

    fn init(loader: ?*c.ke_image_loader, root: ?[*:0]const u8) !Resolver {
        const h = ke_asset_resolver_create(loader, null, root, null);
        try testing.expect(h.ref != null);
        return .{ .handle = h };
    }

    fn api(self: *const Resolver) *c.ke_asset_resolver {
        return @ptrCast(self.handle.ref);
    }

    fn deinit(self: *Resolver) void {
        self.handle.destroy.?(self.handle.ref);
    }
};

fn resolveMesh(r: *const Resolver, path: [*:0]const u8) !c.ke_mesh_shape_data {
    var data = std.mem.zeroes(c.ke_mesh_shape_data);
    const a = r.api();
    try testing.expect(a.resolve_mesh.?(a, path, &data, null));
    return data;
}

fn resolveMaterial(path: [*:0]const u8) !c.ke_material_spec {
    var r = try Resolver.init(null, null);
    defer r.deinit();
    var spec = std.mem.zeroes(c.ke_material_spec);
    const a = r.api();
    try testing.expect(a.resolve_material.?(a, path, &spec, null));
    return spec;
}

test "an absolute texture path is handed to the injected image loader untouched" {
    const loader = resetFakeLoader();
    var img = try TempAsset.init("probe.png", "x");
    defer img.deinit();

    var r = try Resolver.init(loader, null);
    defer r.deinit();

    const a = r.api();
    var data: ?*c.ke_texture_data = null;
    try testing.expect(a.resolve_texture.?(a, img.cPath(), &data, null));
    try testing.expect(data != null);
    try testing.expectEqual(@as(u32, 1), fake_loader_load_count);
    try testing.expectEqualStrings(img.fullPath(), fakeLoaderLastPath());

    a.free_texture.?(a, data);
    try testing.expectEqual(@as(u32, 1), fake_loader_free_count);
}

test "a res prefixed texture path is joined onto the project root" {
    const loader = resetFakeLoader();
    var img = try TempAsset.init("probe.png", "x");
    defer img.deinit();

    var r = try Resolver.init(loader, img.cDir());
    defer r.deinit();

    const a = r.api();
    var data: ?*c.ke_texture_data = null;
    try testing.expect(a.resolve_texture.?(a, "res://probe.png", &data, null));
    try testing.expectEqualStrings(img.fullPath(), fakeLoaderLastPath());

    a.free_texture.?(a, data);
}

test "a texture that is not on disk fails before the loader is ever called" {
    const loader = resetFakeLoader();
    var r = try Resolver.init(loader, null);
    defer r.deinit();

    const a = r.api();
    var data: ?*c.ke_texture_data = null;
    try testing.expect(!a.resolve_texture.?(a, "/this/does/not/exist.png", &data, null));
    try testing.expectEqual(@as(u32, 0), fake_loader_load_count);
}

test "a resolver built without an image loader refuses to resolve a texture" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    const a = r.api();
    var data: ?*c.ke_texture_data = null;
    try testing.expect(!a.resolve_texture.?(a, "anything.png", &data, null));
}

test "every built in primitive resolves to a mesh" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    const names = [_][*:0]const u8{
        "res://primitives/quad",
        "res://primitives/plane",
        "res://primitives/cube",
        "res://primitives/sphere",
    };
    for (names) |name| {
        var data = try resolveMesh(&r, name);
        r.api().free_mesh.?(r.api(), &data);
    }
}

test "each cube face is flat and carries the four corner uvs" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    var data = try resolveMesh(&r, "res://primitives/cube");
    defer r.api().free_mesh.?(r.api(), &data);

    try testing.expectEqual(@as(u32, 24), data.vertex_count);
    try testing.expectEqual(@as(u32, 36), data.index_count);

    const expected_u = [_]f32{ 0.0, 1.0, 1.0, 0.0 };
    const expected_v = [_]f32{ 0.0, 0.0, 1.0, 1.0 };

    for (0..6) |f| {
        const q = data.vertices[f * 4 ..][0..4];
        for (q, 0..) |v, k| {
            try testing.expectApproxEqAbs(q[0].nx, v.nx, geometry_tolerance);
            try testing.expectApproxEqAbs(q[0].ny, v.ny, geometry_tolerance);
            try testing.expectApproxEqAbs(q[0].nz, v.nz, geometry_tolerance);
            try testing.expectApproxEqAbs(expected_u[k], v.u, geometry_tolerance);
            try testing.expectApproxEqAbs(expected_v[k], v.v, geometry_tolerance);
            try testing.expectApproxEqAbs(@as(f32, 0.5), @abs(v.x), geometry_tolerance);
            try testing.expectApproxEqAbs(@as(f32, 0.5), @abs(v.y), geometry_tolerance);
            try testing.expectApproxEqAbs(@as(f32, 0.5), @abs(v.z), geometry_tolerance);
        }
        const axis_sum = @abs(q[0].nx) + @abs(q[0].ny) + @abs(q[0].nz);
        try testing.expectApproxEqAbs(@as(f32, 1.0), axis_sum, geometry_tolerance);
    }

    for (0..6) |a| {
        for (a + 1..6) |b| {
            const va = data.vertices[a * 4];
            const vb = data.vertices[b * 4];
            const same = @abs(va.nx - vb.nx) < geometry_tolerance and
                @abs(va.ny - vb.ny) < geometry_tolerance and
                @abs(va.nz - vb.nz) < geometry_tolerance;
            try testing.expect(!same);
        }
    }

    for (data.indices[0..data.index_count]) |i| {
        try testing.expect(i < data.vertex_count);
    }
}

test "every sphere vertex sits on a half unit radius with a unit normal" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    var data = try resolveMesh(&r, "res://primitives/sphere");
    defer r.api().free_mesh.?(r.api(), &data);

    try testing.expect(data.vertex_count > 0);
    for (data.vertices[0..data.vertex_count]) |v| {
        const radius = @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
        try testing.expectApproxEqAbs(@as(f32, 0.5), radius, geometry_tolerance);
        const normal_len = @sqrt(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz);
        try testing.expectApproxEqAbs(@as(f32, 1.0), normal_len, geometry_tolerance);
    }
    for (data.indices[0..data.index_count]) |i| {
        try testing.expect(i < data.vertex_count);
    }
}

test "a resolved quad faces the camera while a resolved plane faces up" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    var quad = try resolveMesh(&r, "res://primitives/quad");
    defer r.api().free_mesh.?(r.api(), &quad);
    var plane = try resolveMesh(&r, "res://primitives/plane");
    defer r.api().free_mesh.?(r.api(), &plane);

    try testing.expectApproxEqAbs(@as(f32, 1.0), quad.vertices[0].nz, geometry_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 1.0), plane.vertices[0].ny, geometry_tolerance);
    try testing.expectApproxEqAbs(@as(f32, -0.5), quad.vertices[0].x, geometry_tolerance);
    try testing.expectApproxEqAbs(@as(f32, -0.5), quad.vertices[0].y, geometry_tolerance);
}

test "a primitive name the baker does not know is not found" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    const a = r.api();
    var data = std.mem.zeroes(c.ke_mesh_shape_data);
    try testing.expect(!a.resolve_mesh.?(a, "res://primitives/teapot", &data, null));
}

test "a mesh reference outside the primitive namespace is not found" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    const a = r.api();
    var data = std.mem.zeroes(c.ke_mesh_shape_data);
    try testing.expect(!a.resolve_mesh.?(a, "external.gltf", &data, null));
}

test "a path carrying backslashes still reaches the loader as authored" {
    const loader = resetFakeLoader();
    var img = try TempAsset.init("probe.png", "x");
    defer img.deinit();

    var r = try Resolver.init(loader, null);
    defer r.deinit();

    const a = r.api();
    var data: ?*c.ke_texture_data = null;
    try testing.expect(a.resolve_texture.?(a, img.cPath(), &data, null));
    try testing.expectEqualStrings(img.fullPath(), fakeLoaderLastPath());
    a.free_texture.?(a, data);
}

test "a material file that is not toml fails to resolve" {
    var mat = try TempAsset.init("broken.material", "not toml [ [ [");
    defer mat.deinit();

    var r = try Resolver.init(null, null);
    defer r.deinit();

    const a = r.api();
    var spec = std.mem.zeroes(c.ke_material_spec);
    try testing.expect(!a.resolve_material.?(a, mat.cPath(), &spec, null));
}

test "a material that names no alpha mode resolves as opaque with the default cutoff" {
    var mat = try TempAsset.init("m.material", "[material]\nbase_color = [1.0, 1.0, 1.0, 1.0]\n");
    defer mat.deinit();

    const spec = try resolveMaterial(mat.cPath());
    try testing.expectEqual(@as(@TypeOf(spec.alpha_mode), c.KE_ALPHA_MODE_OPAQUE), spec.alpha_mode);
    try testing.expectApproxEqAbs(@as(f32, 0.5), spec.alpha_cutoff, material_tolerance);
}

test "a masked material carries both its mode and its authored cutoff" {
    var mat = try TempAsset.init("m.material", "[material]\nalpha_mode = \"MASK\"\nalpha_cutoff = 0.75\n");
    defer mat.deinit();

    const spec = try resolveMaterial(mat.cPath());
    try testing.expectEqual(@as(@TypeOf(spec.alpha_mode), c.KE_ALPHA_MODE_MASK), spec.alpha_mode);
    try testing.expectApproxEqAbs(@as(f32, 0.75), spec.alpha_cutoff, material_tolerance);
}

test "a blended material resolves to the blend mode" {
    var mat = try TempAsset.init("m.material", "[material]\nalpha_mode = \"BLEND\"\n");
    defer mat.deinit();

    const spec = try resolveMaterial(mat.cPath());
    try testing.expectEqual(@as(@TypeOf(spec.alpha_mode), c.KE_ALPHA_MODE_BLEND), spec.alpha_mode);
}

test "an alpha mode nobody recognises falls back to opaque instead of failing the load" {
    var mat = try TempAsset.init("m.material", "[material]\nalpha_mode = \"typo\"\n");
    defer mat.deinit();

    const spec = try resolveMaterial(mat.cPath());
    try testing.expectEqual(@as(@TypeOf(spec.alpha_mode), c.KE_ALPHA_MODE_OPAQUE), spec.alpha_mode);
}

test "a material that names no index of refraction defaults to glass" {
    var mat = try TempAsset.init("m.material", "[material]\nbase_color = [1.0, 1.0, 1.0, 1.0]\n");
    defer mat.deinit();

    const spec = try resolveMaterial(mat.cPath());
    try testing.expectApproxEqAbs(@as(f32, 1.5), spec.ior, material_tolerance);
}

test "an authored index of refraction overrides the glass default" {
    var mat = try TempAsset.init("m.material", "[material]\nalpha_mode = \"BLEND\"\nior = 1.33\n");
    defer mat.deinit();

    const spec = try resolveMaterial(mat.cPath());
    try testing.expectApproxEqAbs(@as(f32, 1.33), spec.ior, material_tolerance);
}

test "a material that names no distortion strength gets a subtle default" {
    var mat = try TempAsset.init("m.material", "[material]\nbase_color = [1.0, 1.0, 1.0, 1.0]\n");
    defer mat.deinit();

    const spec = try resolveMaterial(mat.cPath());
    try testing.expectApproxEqAbs(@as(f32, 0.05), spec.distortion_strength, material_tolerance);
}

test "an authored distortion strength overrides the default" {
    var mat = try TempAsset.init("m.material", "[material]\nalpha_mode = \"BLEND\"\ndistortion_strength = 0.2\n");
    defer mat.deinit();

    const spec = try resolveMaterial(mat.cPath());
    try testing.expectApproxEqAbs(@as(f32, 0.2), spec.distortion_strength, material_tolerance);
}

test "a resolver with neither a loader nor a project root is still constructible" {
    const h = ke_asset_resolver_create(null, null, null, null);
    try testing.expect(h.ref != null);
    try testing.expect(h.destroy != null);
    h.destroy.?(h.ref);
}

test "resolving a texture through a null self, path or output is rejected" {
    var r = try Resolver.init(resetFakeLoader(), null);
    defer r.deinit();

    const a = r.api();
    var data: ?*c.ke_texture_data = null;
    try testing.expect(!a.resolve_texture.?(null, "test.png", &data, null));
    try testing.expect(!a.resolve_texture.?(a, null, &data, null));
    try testing.expect(!a.resolve_texture.?(a, "test.png", null, null));
}

test "resolving a mesh through a null self, path or output is rejected" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    const a = r.api();
    var data = std.mem.zeroes(c.ke_mesh_shape_data);
    try testing.expect(!a.resolve_mesh.?(null, "res://primitives/cube", &data, null));
    try testing.expect(!a.resolve_mesh.?(a, null, &data, null));
    try testing.expect(!a.resolve_mesh.?(a, "res://primitives/cube", null, null));
}

test "resolving a material through a null self, path or output is rejected" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    const a = r.api();
    var spec = std.mem.zeroes(c.ke_material_spec);
    try testing.expect(!a.resolve_material.?(null, "test.material", &spec, null));
    try testing.expect(!a.resolve_material.?(a, null, &spec, null));
    try testing.expect(!a.resolve_material.?(a, "test.material", null, null));
}

test "freeing a texture through a null self or a null texture is harmless" {
    var r = try Resolver.init(resetFakeLoader(), null);
    defer r.deinit();

    const a = r.api();
    a.free_texture.?(null, null);
    a.free_texture.?(a, null);
    try testing.expectEqual(@as(u32, 0), fake_loader_free_count);
}

test "freeing a mesh through a null self or a null mesh is harmless" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    const a = r.api();
    a.free_mesh.?(null, null);
    a.free_mesh.?(a, null);
}

test "destroying a null resolver is harmless" {
    var r = try Resolver.init(null, null);
    defer r.deinit();

    r.handle.destroy.?(null);
}

test "without a project root a res prefixed path keeps only what follows the prefix" {
    var mat = try TempAsset.init("m.material", "[material]\nbase_color = [1.0, 1.0, 1.0, 1.0]\n");
    defer mat.deinit();

    var r = try Resolver.init(resetFakeLoader(), null);
    defer r.deinit();

    var ref_buf: [std.fs.max_path_bytes]u8 = undefined;
    const ref = try std.fmt.bufPrint(&ref_buf, "res://{s}", .{mat.fullPath()});
    ref_buf[ref.len] = 0;

    const a = r.api();
    var spec = std.mem.zeroes(c.ke_material_spec);
    try testing.expect(a.resolve_material.?(a, @ptrCast(&ref_buf), &spec, null));
}

test "the none handle of every render resource is all bits zero" {
    try testing.expectEqual(@as(u32, 0), c.KE_MESH_NONE.bits);
    try testing.expectEqual(@as(u32, 0), c.KE_TEXTURE_NONE.bits);
    try testing.expectEqual(@as(u32, 0), c.KE_MATERIAL_NONE.bits);
    try testing.expectEqual(@as(u32, 0), c.KE_CUBEMAP_NONE.bits);
    try testing.expectEqual(@as(u32, 0), c.KE_SHADOW_MAP_NONE.bits);

    const zeroed = std.mem.zeroes(c.ke_mesh_handle);
    try testing.expectEqual(@as(u32, c.KE_HANDLE_NONE), zeroed.bits);
}

test "a live handle is never zero, not even at index zero" {
    for (0..8) |index| {
        const bits = handles.make(@intCast(index), c.KE_HANDLE_GENERATION_FIRST);
        const h = c.ke_mesh_handle{ .bits = bits };
        try testing.expect(h.bits != c.KE_HANDLE_NONE);
        try testing.expectEqual(@as(u32, @intCast(index)), handles.index(h.bits));
        try testing.expectEqual(
            @as(u32, c.KE_HANDLE_GENERATION_FIRST),
            handles.generation(h.bits),
        );
    }
}

test "a res:// path joins the project root and any other path stands as written" {
    const h = ke_asset_resolver_create(null, null, "/game", null);
    defer h.destroy.?(h.ref);
    const r = h.ref.?;
    var out: [64]u8 = undefined;

    try testing.expect(r.*.resolve_path.?(r, "res://scenes/a.toml", &out, out.len, null));
    try testing.expectEqualStrings("/game/scenes/a.toml", std.mem.sliceTo(&out, 0));
    try testing.expect(r.*.resolve_path.?(r, "other/b.toml", &out, out.len, null));
    try testing.expectEqualStrings("other/b.toml", std.mem.sliceTo(&out, 0));
}

test "a resolved path that does not fit is refused rather than cut" {
    const h = ke_asset_resolver_create(null, null, "/game", null);
    defer h.destroy.?(h.ref);
    const r = h.ref.?;
    var out: [8]u8 = undefined;
    var err: [*c]c.ke_error = null;

    try testing.expect(!r.*.resolve_path.?(r, "res://scenes/a.toml", &out, out.len, &err));
    try testing.expectEqual(E.typeOf(.invalid_argument), err.*.type);
}

test "creating and destroying a resolver leaves no block allocated" {
    const h = ke_asset_resolver_create(null, null, null, null);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

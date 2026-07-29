// ke_asset_resolver impl. Maps res:// / absolute / relative paths to CPU-side
// asset data via injected loaders (image_loader today; mesh loader slot
// reserved). Material parsing is an internal helper exposed only through the
// resolve_material vtable method — the framework plugin's external surface is
// vtables + factories, nothing else.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

const mesh_shape = @import("mesh_shape.zig");

const res_prefix = "res://";
const primitive_prefix = "res://primitives/";

/// Longest resolved filesystem path this resolver will produce.
const path_buf_max = 1024;

const State = struct {
    api: c.ke_asset_resolver,
    image_loader: ?*c.ke_image_loader, // borrowed; may be null
    font_loader: ?*c.ke_font_loader, // borrowed; may be null
    project_root: ?[:0]u8, // owned; may be null
};

fn stateOf(self: *c.ke_asset_resolver) *State {
    return @ptrCast(@alignCast(self.handle));
}

// -- helpers -----------------------------------------------------------------

fn dupCStr(s: [*c]const u8) ?[:0]u8 {
    if (s == null) return null;
    return heap.gpa.dupeZ(u8, std.mem.span(s)) catch null;
}

fn fileExists(path: [*:0]const u8) bool {
    const f = std.c.fopen(path, "rb") orelse return false;
    _ = std.c.fclose(f);
    return true;
}

/// Copies `src` into `dst` truncating to fit, always NUL-terminating.
fn copyStringClamped(dst: []u8, src: []const u8) void {
    if (dst.len == 0) return;
    const n = @min(src.len, dst.len - 1);
    @memcpy(dst[0..n], src[0..n]);
    dst[n] = 0;
}

/// Joins root and remainder, inserting a '/' only when neither side supplies
/// one. Truncates to fit `out`.
fn joinPath(out: []u8, root: []const u8, remainder: []const u8) void {
    if (out.len == 0) return;
    const need_sep = root.len > 0 and
        root[root.len - 1] != '/' and root[root.len - 1] != '\\' and
        (remainder.len == 0 or (remainder[0] != '/' and remainder[0] != '\\'));

    var i: usize = 0;
    for (root) |ch| {
        if (i >= out.len - 1) break;
        out[i] = ch;
        i += 1;
    }
    if (need_sep and i < out.len - 1) {
        out[i] = '/';
        i += 1;
    }
    for (remainder) |ch| {
        if (i >= out.len - 1) break;
        out[i] = ch;
        i += 1;
    }
    out[i] = 0;
}

/// res://x -> project_root/x ; anything else passes through unchanged.
fn resolvePath(s: *const State, path: [*:0]const u8, out: []u8) void {
    const p = std.mem.span(path);
    if (std.mem.startsWith(u8, p, res_prefix)) {
        const remainder = p[res_prefix.len..];
        if (s.project_root) |root| {
            joinPath(out, root, remainder);
        } else {
            copyStringClamped(out, remainder);
        }
        return;
    }
    copyStringClamped(out, p);
}

// -- internal material parser ------------------------------------------------

/// Reads a numeric TOML key that may be written as either a float or an int.
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

/// Parses a `.material` TOML file. Defaults applied for missing keys. Returns
/// false on missing/unparseable file or absent [material] section.
fn parseMaterialFile(path: [*:0]const u8, out: *c.ke_material_spec) bool {
    // Defaults: white, non-metallic, mid-roughness, no textures.
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

    const fp = std.c.fopen(path, "rb") orelse return false;
    var errbuf: [200]u8 = undefined;
    const root = c.toml_parse_file(@ptrCast(@alignCast(fp)), &errbuf, errbuf.len);
    _ = std.c.fclose(fp);
    if (root == null) return false;
    defer c.toml_free(root);

    const mat = c.toml_table_in(root, "material") orelse return false;

    if (c.toml_array_in(mat, "base_color")) |bc| {
        for (0..4) |i| {
            if (tomlNumberAt(bc, @intCast(i))) |f| out.base_color[i] = f;
        }
    }

    if (tomlNumberIn(mat, "metallic")) |f| out.metallic = f;
    if (tomlNumberIn(mat, "roughness")) |f| out.roughness = f;
    if (tomlNumberIn(mat, "alpha_cutoff")) |f| out.alpha_cutoff = f;
    // ior is only meaningful for BLEND, but is parsed unconditionally like every
    // other factor — the field is simply inert elsewhere.
    if (tomlNumberIn(mat, "ior")) |f| out.ior = f;
    if (tomlNumberIn(mat, "distortion_strength")) |f| out.distortion_strength = f;

    // The strings below are tomlc99's, allocated with malloc inside the parser,
    // so they go back to free() rather than to the plugin heap.
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

    // glTF-aligned: "OPAQUE" | "MASK" | "BLEND". Unknown values keep the OPAQUE
    // default rather than erroring — a typo should not fail a whole scene load.
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

    return true;
}

// -- vtable methods ----------------------------------------------------------

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
    resolvePath(s, path, &buf);
    const resolved: [*:0]const u8 = @ptrCast(&buf);
    if (!fileExists(resolved)) {
        E.fail(out_error, .not_found, "texture file not found", @src());
        return false;
    }

    out.* = loader.load_image.?(loader, resolved, out_error);
    return out.* != null;
}

fn vtFreeTexture(self_in: ?*c.ke_asset_resolver, data: ?*c.ke_texture_data) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or data == null) return;
    const s = stateOf(self);
    if (s.image_loader) |loader| {
        if (loader.free_image) |free_image| free_image(loader, data);
    }
}

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
    // Future: dispatch .gltf/.fbx/.obj via an injected ke_asset_loader.
    E.fail(out_error, .not_found, "mesh not found", @src());
    return false;
}

fn vtFreeMesh(self_in: ?*c.ke_asset_resolver, data: ?*c.ke_mesh_shape_data) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or data == null) return;
    mesh_shape.ke_mesh_shape_free_internal(data);
}

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
    resolvePath(s, path, &buf);
    if (!parseMaterialFile(@ptrCast(&buf), out.?)) {
        E.fail(out_error, .io, "failed to parse material file", @src());
        return false;
    }
    return true;
}

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
    resolvePath(s, path, &buf);
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

fn vtFreeFont(self_in: ?*c.ke_asset_resolver, data: ?*c.ke_font_data) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or data == null) return;
    const s = stateOf(self);
    if (s.font_loader) |loader| {
        if (loader.free_font) |free_font| free_font(loader, data);
    }
}

// -- cached load-from-path ---------------------------------------------------

fn vtResolveTextureInto(
    self_in: ?*c.ke_asset_resolver,
    core_in: ?*c.ke_render_core,
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
    if (core.try_get_texture.?(core, path, &cached) != 0) return cached;

    var data: ?*c.ke_texture_data = null;
    if (!vtResolveTexture(self, path, &data, out_error)) return c.KE_TEXTURE_NONE;

    const d = data.?;
    const h = core.upload_texture.?(core, path, d.width, d.height, d.pixels, out_error);
    vtFreeTexture(self, data);
    return h;
}

/// ke_render_core's vertex-buffer layout is 11 floats (pos3+nrm3+uv2+tan3);
/// ke_vertex carries a 12th (bitangent-sign tw) the GPU pipeline never binds.
const gpu_floats_per_vertex = 11;

fn vtResolveMeshInto(
    self_in: ?*c.ke_asset_resolver,
    core_in: ?*c.ke_render_core,
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
    if (core.try_get_mesh.?(core, path, &cached) != 0) return cached;

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

fn vtResolveMaterialInto(
    self_in: ?*c.ke_asset_resolver,
    core_in: ?*c.ke_render_core,
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
    if (core.try_get_material.?(core, path, &cached) != 0) return cached;

    var spec: c.ke_material_spec = undefined;
    if (!vtResolveMaterial(self, path, &spec, out_error)) return c.KE_MATERIAL_NONE;

    var albedo = c.KE_TEXTURE_NONE;
    if (spec.albedo_path[0] != 0) {
        albedo = vtResolveTextureInto(self, core, @ptrCast(&spec.albedo_path), out_error);
        if (!c.ke_texture_is_valid(albedo)) return c.KE_MATERIAL_NONE;
    }
    var normal = c.KE_TEXTURE_NONE;
    if (spec.normal_path[0] != 0) {
        normal = vtResolveTextureInto(self, core, @ptrCast(&spec.normal_path), out_error);
        if (!c.ke_texture_is_valid(normal)) return c.KE_MATERIAL_NONE;
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

fn vtDestroy(self_in: ?*c.ke_asset_resolver) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.project_root) |root| heap.gpa.free(root);
    heap.gpa.destroy(s);
}

// -- factory -----------------------------------------------------------------

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

    return .{ .ref = &s.api, .destroy = vtDestroy };
}

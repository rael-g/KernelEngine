//! The render assets: the textures, meshes and materials a render service holds, each made once from
//! what the asset resolver reads at a path and found by that path afterwards.

const std = @import("std");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_mesh = @import("abi_mesh");
const abi_mesh_data = @import("abi_mesh_data");
const abi_part = @import("abi_part");
const abi_render = @import("abi_render");
const abi_render_handles = @import("abi_render_handles");
const abi_render_material = @import("abi_render_material");
const abi_result = @import("abi_result");
const heap = @import("heap");
const part = @import("part");

const R = @import("result").Result(.{});

/// The render assets' state: the vtable it hands out, the resolver that reads each asset and the
/// service that holds what it makes. Neither is owned.
const State = struct {
    api: abi_render.c.ke_render_assets,
    resolver: *abi_asset_resolver.c.ke_asset_resolver,
    service: *abi_render.c.ke_render_service,
};

fn stateOf(self: *abi_render.c.ke_render_assets) *State {
    return @ptrCast(@alignCast(self.handle.?));
}

/// Slot `resolve_texture`. A path the service holds costs no file access. The texture is uploaded
/// under the authored path, so the service finds it by what the caller wrote.
fn resolveTexture(self_in: ?*abi_render.c.ke_render_assets, path: [*c]const u8, out_texture: ?*abi_render_handles.c.ke_texture_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_texture orelse return R.code(error.InvalidArgument);
    out.* = abi_render_handles.c.KE_TEXTURE_NONE;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or path == null) return R.code(error.InvalidArgument);
    out.* = texture(stateOf(self), path) catch |err| return R.code(err);
    return R.ok;
}

fn texture(s: *State, path: [*:0]const u8) R.Error!abi_render_handles.c.ke_texture_handle {
    var cached: abi_render_handles.c.ke_texture_handle = undefined;
    if (s.service.try_get_texture.?(s.service, path, &cached)) return cached;

    var data: ?*abi_mesh_data.c.ke_texture_data = null;
    try R.check(s.resolver.resolve_texture.?(s.resolver, path, @ptrCast(&data)));
    defer s.resolver.free_texture.?(s.resolver, data);
    const d = data.?;
    var h = abi_render_handles.c.KE_TEXTURE_NONE;
    try R.check(s.service.upload_texture.?(s.service, path, d.width, d.height, @ptrCast(d.pixels), @as(usize, d.width) * d.height * 4, &h));
    return h;
}

/// Slot `resolve_mesh`. A path the service holds costs no bake. The resolved vertices are uploaded
/// in the layout the service takes, and the shape is freed before the call returns.
fn resolveMesh(self_in: ?*abi_render.c.ke_render_assets, path: [*c]const u8, out_mesh: ?*abi_render_handles.c.ke_mesh_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_mesh orelse return R.code(error.InvalidArgument);
    out.* = abi_render_handles.c.KE_MESH_NONE;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or path == null) return R.code(error.InvalidArgument);
    out.* = mesh(stateOf(self), path) catch |err| return R.code(err);
    return R.ok;
}

fn mesh(s: *State, path: [*:0]const u8) R.Error!abi_render_handles.c.ke_mesh_handle {
    var cached: abi_render_handles.c.ke_mesh_handle = undefined;
    if (s.service.try_get_mesh.?(s.service, path, &cached)) return cached;

    var shape: ?*abi_mesh_data.c.ke_mesh_shape_data = null;
    try R.check(s.resolver.resolve_mesh.?(s.resolver, path, @ptrCast(&shape)));
    defer s.resolver.free_mesh.?(s.resolver, shape);
    const sh = shape.?;

    const vertices = heap.gpa.alloc(abi_mesh.c.ke_mesh_vertex, sh.vertex_count) catch return error.OutOfMemory;
    defer heap.gpa.free(vertices);
    for (vertices, sh.vertices.?[0..sh.vertex_count]) |*dst, v| {
        dst.* = .{
            .position = .{ .x = v.x, .y = v.y, .z = v.z },
            .normal = .{ .x = v.nx, .y = v.ny, .z = v.nz },
            .uv = .{ .x = v.u, .y = v.v },
            .tangent = .{ .x = v.tx, .y = v.ty, .z = v.tz },
        };
    }

    var h = abi_render_handles.c.KE_MESH_NONE;
    try R.check(s.service.upload_mesh.?(s.service, path, @ptrCast(vertices.ptr), sh.vertex_count, sh.indices, sh.index_count, &h));
    return h;
}

/// Slot `resolve_material`. A path the service holds costs no file access. The albedo and normal
/// textures go through `texture`, each found by its own path, and a failure there ends the call
/// before the material is created.
fn resolveMaterial(self_in: ?*abi_render.c.ke_render_assets, path: [*c]const u8, out_material: ?*abi_render_handles.c.ke_material_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_material orelse return R.code(error.InvalidArgument);
    out.* = abi_render_handles.c.KE_MATERIAL_NONE;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or path == null) return R.code(error.InvalidArgument);
    out.* = material(stateOf(self), path) catch |err| return R.code(err);
    return R.ok;
}

fn material(s: *State, path: [*:0]const u8) R.Error!abi_render_handles.c.ke_material_handle {
    var cached: abi_render_handles.c.ke_material_handle = undefined;
    if (s.service.try_get_material.?(s.service, path, &cached)) return cached;

    var spec: abi_render_material.c.ke_material_spec = undefined;
    try R.check(s.resolver.resolve_material.?(s.resolver, path, @ptrCast(&spec)));

    var albedo = abi_render_handles.c.KE_TEXTURE_NONE;
    if (spec.albedo_path[0] != 0) albedo = try texture(s, @ptrCast(&spec.albedo_path));
    var normal = abi_render_handles.c.KE_TEXTURE_NONE;
    if (spec.normal_path[0] != 0) normal = try texture(s, @ptrCast(&spec.normal_path));

    var h = abi_render_handles.c.KE_MATERIAL_NONE;
    try R.check(s.service.create_material.?(
        s.service,
        path,
        .{ .x = spec.base_color[0], .y = spec.base_color[1], .z = spec.base_color[2], .w = spec.base_color[3] },
        spec.metallic,
        spec.roughness,
        albedo,
        normal,
        @intCast(spec.alpha_mode),
        spec.alpha_cutoff,
        spec.ior,
        spec.distortion_strength,
        null,
        &h,
    ));
    return h;
}

/// The destroy of the handle that `ke_render_assets_create` returns. Frees the state; the resolver
/// and the service are not touched.
fn destroy(self_in: ?*abi_render.c.ke_render_assets) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    heap.gpa.destroy(stateOf(self));
}

/// Factory. The resolver and the service are kept by pointer and must outlive the render assets.
/// A null argument fails as an invalid argument and a failed allocation as out of memory, both
/// leaving the handle zeroed.
export fn ke_render_assets_create(
    resolver_in: ?*abi_asset_resolver.c.ke_asset_resolver,
    service_in: ?*abi_render.c.ke_render_service,
    out_assets: ?*abi_render.c.ke_render_assets_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_assets orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_render.c.ke_render_assets_handle);
    const resolver = resolver_in orelse return R.code(error.InvalidArgument);
    const service = service_in orelse return R.code(error.InvalidArgument);

    const s = heap.gpa.create(State) catch |err| return R.code(err);
    s.* = .{ .api = std.mem.zeroes(abi_render.c.ke_render_assets), .resolver = resolver, .service = service };
    s.api.handle = s;
    s.api.resolve_texture = resolveTexture;
    s.api.resolve_mesh = resolveMesh;
    s.api.resolve_material = resolveMaterial;
    out.* = .{ .ref = &s.api, .destroy = destroy };
    return R.ok;
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(ke_render_assets_create, .{ .name = "render_assets", .slots = &.{ "resolver", "service" } }),
};

const testing = std.testing;
const zsub = @import("zsub");

var pixels = [_]u8{ 1, 2, 3, 4 };
var image = abi_mesh_data.c.ke_texture_data{ .pixels = &pixels, .byte_count = 4, .width = 1, .height = 1, .path = std.mem.zeroes([256]u8) };
var resolved_textures: usize = 0;
var freed_textures: usize = 0;
var uploaded_key: [64]u8 = undefined;

fn holdsNothing(_: zsub.For(abi_render.c.ke_render_service).Args(.try_get_texture)) bool {
    return false;
}

fn holdsEverything(args: zsub.For(abi_render.c.ke_render_service).Args(.try_get_texture)) bool {
    args[2].?.* = .{ .bits = 9 };
    return true;
}

fn readImage(args: zsub.For(abi_asset_resolver.c.ke_asset_resolver).Args(.resolve_texture)) abi_result.c.ke_result {
    resolved_textures += 1;
    args[2].?.* = &image;
    return R.ok;
}

fn missingImage(_: zsub.For(abi_asset_resolver.c.ke_asset_resolver).Args(.resolve_texture)) abi_result.c.ke_result {
    return R.code(error.NotFound);
}

fn freeImage(_: zsub.For(abi_asset_resolver.c.ke_asset_resolver).Args(.free_texture)) void {
    freed_textures += 1;
}

fn uploadTexture(args: zsub.For(abi_render.c.ke_render_service).Args(.upload_texture)) abi_result.c.ke_result {
    const key = std.mem.span(args[1].?);
    @memcpy(uploaded_key[0..key.len], key);
    uploaded_key[key.len] = 0;
    args[6].?.* = .{ .bits = 5 };
    return R.ok;
}

const Fixture = struct {
    resolver: zsub.For(abi_asset_resolver.c.ke_asset_resolver) = undefined,
    service: zsub.For(abi_render.c.ke_render_service) = undefined,
    assets: abi_render.c.ke_render_assets_handle = undefined,

    fn init(f: *Fixture) !void {
        resolved_textures = 0;
        freed_textures = 0;
        try f.resolver.init();
        try f.service.init();
        _ = f.resolver.when(.free_texture).does(freeImage);
        _ = f.service.when(.upload_texture).does(uploadTexture);
        try R.check(ke_render_assets_create(f.resolver.api(), f.service.api(), &f.assets));
    }

    fn deinit(f: *Fixture) void {
        f.assets.destroy.?(f.assets.ref);
        f.service.deinit();
        f.resolver.deinit();
    }
};

test "a texture the service already holds is found without reading the image" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    _ = f.service.when(.try_get_texture).does(holdsEverything);
    _ = f.resolver.when(.resolve_texture).does(readImage);

    var h = abi_render_handles.c.KE_TEXTURE_NONE;
    try R.check(f.assets.ref.?.resolve_texture.?(f.assets.ref, "res://a.png", &h));
    try testing.expectEqual(@as(u32, 9), h.bits);
    try testing.expectEqual(@as(usize, 0), resolved_textures);
}

test "a texture the service lacks is read, uploaded under the authored path and the image freed" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    _ = f.service.when(.try_get_texture).does(holdsNothing);
    _ = f.resolver.when(.resolve_texture).does(readImage);

    var h = abi_render_handles.c.KE_TEXTURE_NONE;
    try R.check(f.assets.ref.?.resolve_texture.?(f.assets.ref, "res://a.png", &h));
    try testing.expectEqual(@as(u32, 5), h.bits);
    try testing.expectEqualStrings("res://a.png", std.mem.sliceTo(&uploaded_key, 0));
    try testing.expectEqual(@as(usize, 1), resolved_textures);
    try testing.expectEqual(@as(usize, 1), freed_textures);
}

test "an image the resolver cannot read fails with its code and leaves no texture" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    _ = f.service.when(.try_get_texture).does(holdsNothing);
    _ = f.resolver.when(.resolve_texture).does(missingImage);

    var h: abi_render_handles.c.ke_texture_handle = .{ .bits = 77 };
    try testing.expectError(error.NotFound, R.check(f.assets.ref.?.resolve_texture.?(f.assets.ref, "res://gone.png", &h)));
    try testing.expectEqual(abi_render_handles.c.KE_HANDLE_NONE, h.bits);
}

test "resolving through a null self, path or output is refused" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const a = f.assets.ref.?;
    var t = abi_render_handles.c.KE_TEXTURE_NONE;
    var m = abi_render_handles.c.KE_MESH_NONE;
    var mat = abi_render_handles.c.KE_MATERIAL_NONE;
    try testing.expectError(error.InvalidArgument, R.check(a.resolve_texture.?(null, "x", &t)));
    try testing.expectError(error.InvalidArgument, R.check(a.resolve_texture.?(a, null, &t)));
    try testing.expectError(error.InvalidArgument, R.check(a.resolve_texture.?(a, "x", null)));
    try testing.expectError(error.InvalidArgument, R.check(a.resolve_mesh.?(a, null, &m)));
    try testing.expectError(error.InvalidArgument, R.check(a.resolve_material.?(a, null, &mat)));
}

test "creating without a resolver or a service is refused and leaves the handle zeroed" {
    var service: zsub.For(abi_render.c.ke_render_service) = undefined;
    try service.init();
    defer service.deinit();
    var h: abi_render.c.ke_render_assets_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_assets_create(null, service.api(), &h)));
    try testing.expect(h.ref == null and h.destroy == null);
}

test "the none handle of every render resource is all bits zero" {
    try testing.expectEqual(@as(u32, 0), abi_render_handles.c.KE_MESH_NONE.bits);
    try testing.expectEqual(@as(u32, 0), abi_render_handles.c.KE_TEXTURE_NONE.bits);
    try testing.expectEqual(@as(u32, 0), abi_render_handles.c.KE_MATERIAL_NONE.bits);
    try testing.expectEqual(@as(u32, 0), abi_render_handles.c.KE_CUBEMAP_NONE.bits);
    try testing.expectEqual(@as(u32, 0), abi_render_handles.c.KE_SHADOW_MAP_NONE.bits);

    const zeroed = std.mem.zeroes(abi_render_handles.c.ke_mesh_handle);
    try testing.expectEqual(@as(u32, abi_render_handles.c.KE_HANDLE_NONE), zeroed.bits);
}

test "creating and destroying render assets leaves no block allocated" {
    var f: Fixture = .{};
    try f.init();
    f.deinit();
    try heap.expectNoLeaks();
}

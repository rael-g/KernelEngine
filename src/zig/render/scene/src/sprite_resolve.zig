//! Gives each 2D sprite a mesh component carrying a quad and a material that match its fields.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_render_handles = @import("abi_render_handles");
const abi_ecs = @import("abi_ecs");
const abi_mesh = @import("abi_mesh");
const abi_math = @import("abi_math");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_scene);

const std = @import("std");

const cache_key = @import("cache_key.zig");
const bitsOf = cache_key.bits;

/// Its memory layout is what `quadFor` uploads as raw bytes, so it is `extern` and not left to
/// the compiler.
const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    tangent: [3]f32,
};

/// The user data of `system`, stored inside the scene resolve's state, whose address the runtime
/// is given. `core` and `resolver` are pointers its creator passed in, and this type does not own
/// them. `resolver` is null when no asset resolver was supplied, and then no texture is ever
/// loaded.
pub const State = struct {
    core: *abi_render.c.ke_render_service,
    mesh_cid: abi_asset_resolver.c.ke_component_id,
    resolver: ?*abi_asset_resolver.c.ke_asset_resolver,
};

/// Uploads a quad for the sprite's shape and returns its handle, which `swapMesh` takes over.
/// The key covers every field the vertices and indices are computed from, so sprites of one
/// shape name the same upload. A failed upload is logged and returns the empty handle.
fn quadFor(core: *abi_render.c.ke_render_service, sp: *const abi_render_components.c.ke_sprite2d_component) abi_render_handles.c.ke_mesh_handle {
    const w = sp.size.x;
    const h = sp.size.y;
    const x0 = -sp.pivot.x * w;
    const x1 = x0 + w;
    const y0 = -sp.pivot.y * h;
    const y1 = y0 + h;

    var uv_x0 = sp.region.x;
    var uv_x1 = sp.region.x + sp.region.z;
    var uv_y0 = sp.region.y + sp.region.w;
    var uv_y1 = sp.region.y;
    if (sp.flip_h != 0) std.mem.swap(f32, &uv_x0, &uv_x1);
    if (sp.flip_v != 0) std.mem.swap(f32, &uv_y0, &uv_y1);

    const n = [3]f32{ 0, 0, 1 };
    const t = [3]f32{ 1, 0, 0 };
    const verts = [4]Vertex{
        .{ .position = .{ x0, y0, 0 }, .normal = n, .uv = .{ uv_x0, uv_y0 }, .tangent = t },
        .{ .position = .{ x1, y0, 0 }, .normal = n, .uv = .{ uv_x1, uv_y0 }, .tangent = t },
        .{ .position = .{ x1, y1, 0 }, .normal = n, .uv = .{ uv_x1, uv_y1 }, .tangent = t },
        .{ .position = .{ x0, y1, 0 }, .normal = n, .uv = .{ uv_x0, uv_y1 }, .tangent = t },
    };
    const idx = [6]u16{ 0, 1, 2, 0, 2, 3 };

    var key: cache_key.Key("sprite", 10) = .{};
    const k = key.init(.{
        bitsOf(w),            bitsOf(h),            bitsOf(sp.pivot.x),   bitsOf(sp.pivot.y), bitsOf(sp.region.x),
        bitsOf(sp.region.y),  bitsOf(sp.region.z),  bitsOf(sp.region.w),  sp.flip_h,     sp.flip_v,
    });

    var mesh: abi_render_handles.c.ke_mesh_handle = abi_render_handles.c.KE_MESH_NONE;
    if (core.upload_mesh.?(core, k, @ptrCast(&verts), verts.len, &idx, idx.len, &mesh) != R.ok)
        log.warn("a sprite quad could not be uploaded", .{});
    return mesh;
}

/// Keeps the resolved handle in `texture_handle` and returns it, so a handle that is not empty
/// skips the resolver from then on. With no resolver the sprite gets the empty texture and
/// nothing is stored, so the next call tries again.
fn resolveTexture(st: *State, sp: *abi_render_components.c.ke_sprite2d_component) abi_render_handles.c.ke_texture_handle {
    if (sp.texture[0] == 0) return abi_render_handles.c.KE_TEXTURE_NONE;
    if (sp.texture_handle.bits != abi_render_handles.c.KE_HANDLE_NONE) return sp.texture_handle;

    const resolver = st.resolver orelse return abi_render_handles.c.KE_TEXTURE_NONE;
    if (resolver.resolve_texture_into.?(resolver, st.core, @ptrCast(&sp.texture), &sp.texture_handle) != abi_result.c.KE_OK)
        sp.texture_handle = abi_render_handles.c.KE_TEXTURE_NONE;
    return sp.texture_handle;
}

/// Asks the core for a material under a key of the color, the resolved texture and the alpha
/// fields, so a change to any of them yields another material. A failed creation is logged and
/// returns the empty handle.
fn materialFor(st: *State, sp: *abi_render_components.c.ke_sprite2d_component) abi_render_handles.c.ke_material_handle {
    const core = st.core;
    const col = sp.color;
    const tex = resolveTexture(st, sp);
    var key: cache_key.Key("sprite", 7) = .{};
    const k = key.init(.{
        bitsOf(col.x), bitsOf(col.y), bitsOf(col.z), bitsOf(col.w), tex.bits, sp.alpha_mode, bitsOf(sp.alpha_cutoff),
    });

    var material: abi_render_handles.c.ke_material_handle = abi_render_handles.c.KE_MATERIAL_NONE;
    const made = core.create_material.?(
        core,
        k,
        sp.color,
        0,
        1,
        tex,
        abi_render_handles.c.KE_TEXTURE_NONE,
        sp.alpha_mode,
        sp.alpha_cutoff,
        1.5,
        0,
        null,
        &material,
    );
    if (made != R.ok) log.warn("a sprite material could not be created", .{});
    return material;
}

/// Takes over the handle passed in and releases the one the component held, so across ticks the
/// component keeps one reference to its mesh rather than one per call.
fn swapMesh(core: *abi_render.c.ke_render_service, m: *abi_render_components.c.ke_mesh_component, resolved: abi_render_handles.c.ke_mesh_handle) void {
    if (resolved.bits == abi_render_handles.c.KE_HANDLE_NONE) return;
    const held = m.mesh;
    m.mesh = resolved;
    if (held.bits != abi_render_handles.c.KE_HANDLE_NONE) core.release_mesh.?(core, held);
}

/// The same convention as `swapMesh`, for the material of the component.
fn swapMaterial(core: *abi_render.c.ke_render_service, m: *abi_render_components.c.ke_mesh_component, resolved: abi_render_handles.c.ke_material_handle) void {
    if (resolved.bits == abi_render_handles.c.KE_HANDLE_NONE) return;
    const held = m.material;
    m.material = resolved;
    if (held.bits != abi_render_handles.c.KE_HANDLE_NONE) core.release_material.?(core, held);
}

/// The update-phase body the module registers, in two passes per tick. The first visits the
/// sprites that already own a mesh component: it marks each as attached and stores a quad and
/// a material built from its fields through `swapMesh` and `swapMaterial`. Both are asked for
/// again every tick under keys spelled from the fields they depend on, so an edit to a sprite
/// yields another object. The second visits the sprites still unmarked, the ones without a mesh
/// component: it marks each and queues an attach of the mesh component on the commands of the
/// context, so the first pass reaches the sprite on a later tick. A refused attach returns the
/// commands' code, and the sprite stays marked, so a later tick does not
/// queue it again. A failed upload, material creation or texture resolve leaves its handle empty.
pub fn system(ctx: ?*abi_runtime.c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const st: *State = @ptrCast(@alignCast(user.?));

    var segc: usize = 0;
    var segs = ctx.?.view.?(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const sprites: [*c]abi_render_components.c.ke_sprite2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        const meshes: [*c]abi_render_components.c.ke_mesh_component = @ptrCast(@alignCast(segs.?[s].columns.?[1]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            const sp: *abi_render_components.c.ke_sprite2d_component = @ptrCast(&sprites[i]);
            sp.attached = 1;
            swapMesh(st.core, @ptrCast(&meshes[i]), quadFor(st.core, sp));
            swapMaterial(st.core, @ptrCast(&meshes[i]), materialFor(st, sp));
        }
    }

    segs = ctx.?.view.?(ctx, 1, &segc);
    s = 0;
    while (s < segc) : (s += 1) {
        const sprites: [*c]abi_render_components.c.ke_sprite2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            if (sprites[i].attached != 0) continue;
            sprites[i].attached = 1;
            const commands = ctx.?.commands;
            const attached = commands.?.attach.?(commands, segs.?[s].entities.?[i], st.mesh_cid, null, 0);
            if (attached != R.ok) return attached;
        }
    }
    return R.ok;
}



const testing = std.testing;

const Capture = struct {
    var key: [192]u8 = undefined;
    var key_len: usize = 0;
    var verts: [4]Vertex = undefined;
    var indices: [6]u16 = undefined;
    var calls: u32 = 0;

    fn reset() void {
        key_len = 0;
        calls = 0;
        verts = std.mem.zeroes([4]Vertex);
        indices = std.mem.zeroes([6]u16);
    }

    fn keySlice() []const u8 {
        return key[0..key_len];
    }
};

fn captureUploadMesh(
    _: [*c]abi_render.c.ke_render_service,
    key: [*c]const u8,
    vertices: [*c]const abi_mesh.c.ke_mesh_vertex,
    _: u32,
    indices: [*c]const u16,
    index_count: u32,
    out: [*c]abi_render_handles.c.ke_mesh_handle,
) callconv(.c) abi_result.c.ke_result {
    const k = std.mem.span(key);
    @memcpy(Capture.key[0..k.len], k);
    Capture.key_len = k.len;
    const v: [*]const Vertex = @ptrCast(vertices.?);
    Capture.verts = v[0..4].*;
    @memcpy(Capture.indices[0..index_count], indices[0..index_count]);
    Capture.calls += 1;
    out.* = .{ .bits = 77 };
    return R.ok;
}

fn fakeService() abi_render.c.ke_render_service {
    var svc = std.mem.zeroes(abi_render.c.ke_render_service);
    svc.upload_mesh = captureUploadMesh;
    return svc;
}

fn defaultSprite() abi_render_components.c.ke_sprite2d_component {
    var sp = std.mem.zeroes(abi_render_components.c.ke_sprite2d_component);
    sp.size = .{ .x = 2, .y = 4 };
    sp.pivot = .{ .x = 0.5, .y = 0.5 };
    sp.region = .{ .x = 0, .y = 0, .z = 1, .w = 1 };
    return sp;
}

test "a centred pivot puts the quad's corners half a size either side of the origin" {
    Capture.reset();
    var svc = fakeService();
    const sp = defaultSprite();
    _ = quadFor(&svc, &sp);
    try testing.expectEqual(@as(f32, -1), Capture.verts[0].position[0]);
    try testing.expectEqual(@as(f32, -2), Capture.verts[0].position[1]);
    try testing.expectEqual(@as(f32, 1), Capture.verts[2].position[0]);
    try testing.expectEqual(@as(f32, 2), Capture.verts[2].position[1]);
}

test "a bottom-left pivot puts the whole quad in the positive quadrant" {
    Capture.reset();
    var svc = fakeService();
    var sp = defaultSprite();
    sp.pivot = .{ .x = 0, .y = 0 };
    _ = quadFor(&svc, &sp);
    try testing.expectEqual(@as(f32, 0), Capture.verts[0].position[0]);
    try testing.expectEqual(@as(f32, 0), Capture.verts[0].position[1]);
    try testing.expectEqual(@as(f32, 2), Capture.verts[2].position[0]);
    try testing.expectEqual(@as(f32, 4), Capture.verts[2].position[1]);
}

test "the quad's texture coordinates start flipped vertically because images are authored top-down" {
    Capture.reset();
    var svc = fakeService();
    const sp = defaultSprite();
    _ = quadFor(&svc, &sp);
    try testing.expectEqual(@as(f32, 0), Capture.verts[0].uv[0]);
    try testing.expectEqual(@as(f32, 1), Capture.verts[0].uv[1]);
    try testing.expectEqual(@as(f32, 1), Capture.verts[2].uv[0]);
    try testing.expectEqual(@as(f32, 0), Capture.verts[2].uv[1]);
}

test "a horizontal flip swaps the horizontal texture coordinates and nothing else" {
    Capture.reset();
    var svc = fakeService();
    var sp = defaultSprite();
    sp.flip_h = 1;
    _ = quadFor(&svc, &sp);
    try testing.expectEqual(@as(f32, 1), Capture.verts[0].uv[0]);
    try testing.expectEqual(@as(f32, 1), Capture.verts[0].uv[1]);
    try testing.expectEqual(@as(f32, -1), Capture.verts[0].position[0]);
}

test "a vertical flip swaps the vertical texture coordinates" {
    Capture.reset();
    var svc = fakeService();
    var sp = defaultSprite();
    sp.flip_v = 1;
    _ = quadFor(&svc, &sp);
    try testing.expectEqual(@as(f32, 0), Capture.verts[0].uv[1]);
    try testing.expectEqual(@as(f32, 1), Capture.verts[2].uv[1]);
}

test "a region draws only that rectangle of the image" {
    Capture.reset();
    var svc = fakeService();
    var sp = defaultSprite();
    sp.region = .{ .x = 0.25, .y = 0.5, .z = 0.25, .w = 0.5 };
    _ = quadFor(&svc, &sp);
    try testing.expectEqual(@as(f32, 0.25), Capture.verts[0].uv[0]);
    try testing.expectEqual(@as(f32, 1.0), Capture.verts[0].uv[1]);
    try testing.expectEqual(@as(f32, 0.5), Capture.verts[2].uv[0]);
    try testing.expectEqual(@as(f32, 0.5), Capture.verts[2].uv[1]);
}

test "every quad faces the viewer with the same normal and tangent" {
    Capture.reset();
    var svc = fakeService();
    const sp = defaultSprite();
    _ = quadFor(&svc, &sp);
    for (Capture.verts) |v| {
        try testing.expectEqual([3]f32{ 0, 0, 1 }, v.normal);
        try testing.expectEqual([3]f32{ 1, 0, 0 }, v.tangent);
    }
}

test "the quad is two triangles sharing the diagonal" {
    Capture.reset();
    var svc = fakeService();
    const sp = defaultSprite();
    _ = quadFor(&svc, &sp);
    try testing.expectEqual([6]u16{ 0, 1, 2, 0, 2, 3 }, Capture.indices);
}

test "two sprites of the same shape share one cache key, and a different shape does not" {
    Capture.reset();
    var svc = fakeService();
    const sp = defaultSprite();
    _ = quadFor(&svc, &sp);
    var first: [192]u8 = undefined;
    const first_len = Capture.key_len;
    @memcpy(first[0..first_len], Capture.keySlice());

    _ = quadFor(&svc, &sp);
    try testing.expectEqualStrings(first[0..first_len], Capture.keySlice());

    var other = sp;
    other.flip_h = 1;
    _ = quadFor(&svc, &other);
    try testing.expect(!std.mem.eql(u8, first[0..first_len], Capture.keySlice()));
}

test "a sprite naming no image resolves to no texture without consulting a resolver" {
    var svc = fakeService();
    var st = State{ .core = &svc, .mesh_cid = 0, .resolver = null };
    var sp = defaultSprite();
    try testing.expectEqual(abi_render_handles.c.KE_TEXTURE_NONE, resolveTexture(&st, &sp));
}

test "a sprite naming an image draws untextured where no resolver was wired" {
    var svc = fakeService();
    var st = State{ .core = &svc, .mesh_cid = 0, .resolver = null };
    var sp = defaultSprite();
    @memcpy(sp.texture[0.."res://sprite.png".len], "res://sprite.png");
    try testing.expectEqual(abi_render_handles.c.KE_TEXTURE_NONE, resolveTexture(&st, &sp));
}

test "an image already uploaded is not resolved a second time" {
    var svc = fakeService();
    var st = State{ .core = &svc, .mesh_cid = 0, .resolver = null };
    var sp = defaultSprite();
    @memcpy(sp.texture[0.."res://sprite.png".len], "res://sprite.png");
    sp.texture_handle = .{ .bits = 9 };
    try testing.expectEqual(@as(u32, 9), resolveTexture(&st, &sp).bits);
}

const Refs = struct {
    var mesh: i32 = 0;
    var material: i32 = 0;
    var next_mesh: u32 = 1;
    var next_material: u32 = 1;

    fn reset() void {
        mesh = 0;
        material = 0;
        next_mesh = 1;
        next_material = 1;
    }
};

fn refUploadMesh(
    _: [*c]abi_render.c.ke_render_service,
    _: [*c]const u8,
    _: [*c]const abi_mesh.c.ke_mesh_vertex,
    _: u32,
    _: [*c]const u16,
    _: u32,
    out: [*c]abi_render_handles.c.ke_mesh_handle,
) callconv(.c) abi_result.c.ke_result {
    Refs.mesh += 1;
    out.* = .{ .bits = 100 };
    return R.ok;
}

fn refCreateMaterial(
    _: [*c]abi_render.c.ke_render_service,
    _: [*c]const u8,
    _: abi_math.c.ke_vec4,
    _: f32,
    _: f32,
    _: abi_render_handles.c.ke_texture_handle,
    _: abi_render_handles.c.ke_texture_handle,
    _: abi_render_handles.c.ke_alpha_mode,
    _: f32,
    _: f32,
    _: f32,
    _: [*c]const u8,
    out: [*c]abi_render_handles.c.ke_material_handle,
) callconv(.c) abi_result.c.ke_result {
    Refs.material += 1;
    out.* = .{ .bits = 200 };
    return R.ok;
}

fn refReleaseMesh(_: [*c]abi_render.c.ke_render_service, _: abi_render_handles.c.ke_mesh_handle) callconv(.c) void {
    Refs.mesh -= 1;
}

fn refReleaseMaterial(_: [*c]abi_render.c.ke_render_service, _: abi_render_handles.c.ke_material_handle) callconv(.c) void {
    Refs.material -= 1;
}

var view_sprites: [1]abi_render_components.c.ke_sprite2d_component = undefined;
var view_meshes: [1]abi_render_components.c.ke_mesh_component = undefined;
var view_entities: [1]abi_asset_resolver.c.ke_entity = .{1};
var view_segment: abi_ecs.c.ke_ecs_segment = undefined;
var view_columns: [2]?*anyopaque = undefined;

fn fakeView(_: [*c]abi_runtime.c.ke_system_ctx, index: u32, out_count: [*c]usize) callconv(.c) [*c]const abi_ecs.c.ke_ecs_segment {
    if (index != 0) {
        out_count.* = 0;
        return null;
    }
    view_segment = std.mem.zeroes(abi_ecs.c.ke_ecs_segment);
    view_segment.count = 1;
    view_segment.entities = &view_entities;
    view_columns = .{ &view_sprites, &view_meshes };
    view_segment.columns = view_columns[0..].ptr;
    view_segment.column_count = 2;
    out_count.* = 1;
    return &view_segment;
}

test "a sprite resolved every tick holds one reference to its mesh and material, not one per tick" {
    Refs.reset();
    var svc = std.mem.zeroes(abi_render.c.ke_render_service);
    svc.upload_mesh = refUploadMesh;
    svc.create_material = refCreateMaterial;
    svc.release_mesh = refReleaseMesh;
    svc.release_material = refReleaseMaterial;
    var st = State{ .core = &svc, .mesh_cid = 0, .resolver = null };

    view_sprites[0] = defaultSprite();
    view_sprites[0].attached = 1;
    view_meshes[0] = std.mem.zeroes(abi_render_components.c.ke_mesh_component);
    var ctx = std.mem.zeroes(abi_runtime.c.ke_system_ctx);
    ctx.view = fakeView;

    for (0..5) |_| try testing.expect(system(&ctx, &st, 0.0) == R.ok);

    try testing.expectEqual(@as(i32, 1), Refs.mesh);
    try testing.expectEqual(@as(i32, 1), Refs.material);
    try testing.expectEqual(@as(u32, 100), view_meshes[0].mesh.bits);
    try testing.expectEqual(@as(u32, 200), view_meshes[0].material.bits);
}

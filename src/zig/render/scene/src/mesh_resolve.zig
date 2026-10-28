//! Gives each mesh component a built-in mesh and a material while its handles are still empty.

const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_scene);

const std = @import("std");

const cache_key = @import("cache_key.zig");
const bitsOf = cache_key.bits;

/// The vertex layout of every built-in shape. The shapes are uploaded as the raw bytes of an array
/// of these, and `extern` fixes the field order those bytes carry.
const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    tangent: [3]f32,
};

/// A unit square in the plane facing the positive z axis, uploaded under the key of the quad.
fn quad(core: *abi_render.ke_render_service, out: *abi_render.ke_mesh_handle) abi_result.ke_result {
    const t = [3]f32{ 1, 0, 0 };
    const verts = [4]Vertex{
        .{ .position = .{ -0.5, -0.5, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 1 }, .tangent = t },
        .{ .position = .{ 0.5, -0.5, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 1, 1 }, .tangent = t },
        .{ .position = .{ 0.5, 0.5, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 1, 0 }, .tangent = t },
        .{ .position = .{ -0.5, 0.5, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 0 }, .tangent = t },
    };
    const idx = [6]u16{ 0, 1, 2, 0, 2, 3 };
    return core.upload_mesh.?(core, "primitive:quad", &verts, @sizeOf(@TypeOf(verts)), &idx, idx.len, out);
}

/// A unit square lying flat with its normal along the positive y axis, uploaded under its own key.
fn plane(core: *abi_render.ke_render_service, out: *abi_render.ke_mesh_handle) abi_result.ke_result {
    const n = [3]f32{ 0, 1, 0 };
    const t = [3]f32{ 1, 0, 0 };
    const verts = [4]Vertex{
        .{ .position = .{ -0.5, 0, -0.5 }, .normal = n, .uv = .{ 0, 0 }, .tangent = t },
        .{ .position = .{ 0.5, 0, -0.5 }, .normal = n, .uv = .{ 1, 0 }, .tangent = t },
        .{ .position = .{ 0.5, 0, 0.5 }, .normal = n, .uv = .{ 1, 1 }, .tangent = t },
        .{ .position = .{ -0.5, 0, 0.5 }, .normal = n, .uv = .{ 0, 1 }, .tangent = t },
    };
    const idx = [6]u16{ 0, 1, 2, 0, 2, 3 };
    return core.upload_mesh.?(core, "primitive:plane", &verts, @sizeOf(@TypeOf(verts)), &idx, idx.len, out);
}

fn sub(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn normalize(v: [3]f32) [3]f32 {
    const len = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (len < 1e-8) return v;
    return .{ v[0] / len, v[1] / len, v[2] / len };
}

/// Gives each face vertices of its own, carrying that face's normal, so no vertex is shared between
/// two faces. The tangent of a face runs along the edge from its first vertex to its second.
fn cube(core: *abi_render.ke_render_service, out: *abi_render.ke_mesh_handle) abi_result.ke_result {
    const h = 0.5;
    var verts: [24]Vertex = undefined;
    var idx: [36]u16 = undefined;

    const Face = struct { n: [3]f32, p0: [3]f32, p1: [3]f32, p2: [3]f32, p3: [3]f32 };
    const faces = [6]Face{
        .{ .n = .{ 1, 0, 0 }, .p0 = .{ h, -h, h }, .p1 = .{ h, -h, -h }, .p2 = .{ h, h, -h }, .p3 = .{ h, h, h } },
        .{ .n = .{ -1, 0, 0 }, .p0 = .{ -h, -h, -h }, .p1 = .{ -h, -h, h }, .p2 = .{ -h, h, h }, .p3 = .{ -h, h, -h } },
        .{ .n = .{ 0, 1, 0 }, .p0 = .{ -h, h, h }, .p1 = .{ h, h, h }, .p2 = .{ h, h, -h }, .p3 = .{ -h, h, -h } },
        .{ .n = .{ 0, -1, 0 }, .p0 = .{ -h, -h, -h }, .p1 = .{ h, -h, -h }, .p2 = .{ h, -h, h }, .p3 = .{ -h, -h, h } },
        .{ .n = .{ 0, 0, 1 }, .p0 = .{ -h, -h, h }, .p1 = .{ h, -h, h }, .p2 = .{ h, h, h }, .p3 = .{ -h, h, h } },
        .{ .n = .{ 0, 0, -1 }, .p0 = .{ h, -h, -h }, .p1 = .{ -h, -h, -h }, .p2 = .{ -h, h, -h }, .p3 = .{ h, h, -h } },
    };
    for (faces, 0..) |f, fi| {
        const v = fi * 4;
        const t = normalize(sub(f.p1, f.p0));
        verts[v + 0] = .{ .position = f.p0, .normal = f.n, .uv = .{ 0, 1 }, .tangent = t };
        verts[v + 1] = .{ .position = f.p1, .normal = f.n, .uv = .{ 1, 1 }, .tangent = t };
        verts[v + 2] = .{ .position = f.p2, .normal = f.n, .uv = .{ 1, 0 }, .tangent = t };
        verts[v + 3] = .{ .position = f.p3, .normal = f.n, .uv = .{ 0, 0 }, .tangent = t };
        const i = fi * 6;
        idx[i + 0] = @intCast(v + 0);
        idx[i + 1] = @intCast(v + 1);
        idx[i + 2] = @intCast(v + 2);
        idx[i + 3] = @intCast(v + 0);
        idx[i + 4] = @intCast(v + 2);
        idx[i + 5] = @intCast(v + 3);
    }
    return core.upload_mesh.?(core, "primitive:cube", &verts, @sizeOf(@TypeOf(verts)), &idx, idx.len, out);
}

const sphere_rings = 24;
const sphere_segments = 32;

/// Builds a grid with one more vertex per ring than it has cells. The extra vertex repeats the
/// position of the first one in its ring, with the texture coordinate at the far edge.
fn uvSphere(core: *abi_render.ke_render_service, out: *abi_render.ke_mesh_handle) abi_result.ke_result {
    const radius = 0.5;
    const vert_count = (sphere_rings + 1) * (sphere_segments + 1);
    const idx_count = sphere_rings * sphere_segments * 6;
    var verts: [vert_count]Vertex = undefined;
    var idx: [idx_count]u16 = undefined;

    var vi: usize = 0;
    var r: usize = 0;
    while (r <= sphere_rings) : (r += 1) {
        const phi = std.math.pi * @as(f32, @floatFromInt(r)) / sphere_rings;
        const y = @cos(phi);
        const sin_p = @sin(phi);
        var s: usize = 0;
        while (s <= sphere_segments) : (s += 1) {
            const theta = 2.0 * std.math.pi * @as(f32, @floatFromInt(s)) / sphere_segments;
            const n = [3]f32{ sin_p * @cos(theta), y, sin_p * @sin(theta) };
            const t = [3]f32{ -@sin(theta), 0, @cos(theta) };
            verts[vi] = .{
                .position = .{ n[0] * radius, n[1] * radius, n[2] * radius },
                .normal = n,
                .uv = .{ @as(f32, @floatFromInt(s)) / sphere_segments, @as(f32, @floatFromInt(r)) / sphere_rings },
                .tangent = t,
            };
            vi += 1;
        }
    }

    var ii: usize = 0;
    r = 0;
    while (r < sphere_rings) : (r += 1) {
        var s: usize = 0;
        while (s < sphere_segments) : (s += 1) {
            const a = r * (sphere_segments + 1) + s;
            const b = a + 1;
            const cc = (r + 1) * (sphere_segments + 1) + s;
            const d = cc + 1;
            idx[ii + 0] = @intCast(a);
            idx[ii + 1] = @intCast(cc);
            idx[ii + 2] = @intCast(b);
            idx[ii + 3] = @intCast(b);
            idx[ii + 4] = @intCast(cc);
            idx[ii + 5] = @intCast(d);
            ii += 6;
        }
    }
    return core.upload_mesh.?(core, "primitive:sphere:0.5:24:32", &verts, @sizeOf(@TypeOf(verts)), &idx, idx.len, out);
}

/// Maps the name in the component's primitive field to one of the built-in shapes, uploaded
/// under a key that names the shape, so components of one shape share one upload. Leaves the
/// component alone when it has a mesh or names no primitive, and stores no handle for a name
/// that is none of the built-in shapes or a shape whose upload fails.
fn resolveMesh(core: *abi_render.ke_render_service, m: [*c]abi_render.ke_mesh_component) void {
    const mc: *abi_render.ke_mesh_component = @ptrCast(m);
    if (mc.mesh.bits != abi_render.KE_HANDLE_NONE or mc.primitive[0] == 0) return;
    const name = std.mem.sliceTo(&mc.primitive, 0);
    const shapes = .{ .{ "quad", quad }, .{ "plane", plane }, .{ "cube", cube }, .{ "sphere", uvSphere } };
    inline for (shapes) |shape| {
        if (std.mem.eql(u8, name, shape[0])) {
            if (shape[1](core, &mc.mesh) != R.ok) log.warn("the {s} primitive could not be uploaded", .{shape[0]});
            return;
        }
    }
}

/// The key spells every value this call varies, so a material's key changes whenever one of the
/// values that shade it does. The textures passed are always none.
fn resolveMaterial(core: *abi_render.ke_render_service, m: [*c]abi_render.ke_mesh_component) void {
    const mc: *abi_render.ke_mesh_component = @ptrCast(m);
    if (mc.material.bits != abi_render.KE_HANDLE_NONE) return;
    const bc = mc.base_color;

    var key: cache_key.Key("inline", 9) = .{};
    const k = key.init(.{
        bitsOf(bc.x),         bitsOf(bc.y),        bitsOf(bc.z),
        bitsOf(bc.w),         bitsOf(mc.roughness), mc.alpha_mode,
        bitsOf(mc.alpha_cutoff), bitsOf(mc.ior),       bitsOf(mc.distortion_strength),
    });

    const made = core.create_material.?(
        core,
        k,
        @ptrCast(&mc.base_color),
        0,
        mc.roughness,
        abi_render.KE_TEXTURE_NONE,
        abi_render.KE_TEXTURE_NONE,
        mc.alpha_mode,
        mc.alpha_cutoff,
        mc.ior,
        mc.distortion_strength,
        null,
        &mc.material,
    );
    if (made != R.ok) log.warn("an inline material could not be created", .{});
}

/// Runs in the update phase over the mesh view. For every component it runs `resolveMesh` and
/// then `resolveMaterial`, each only while its handle is still empty. It always succeeds: a failed
/// upload or creation is logged, leaves the handle empty and is attempted again on the next pass.
pub fn system(ctx: ?*abi_runtime.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const core: *abi_render.ke_render_service = @ptrCast(@alignCast(user.?));

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const meshes: [*c]abi_render.ke_mesh_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            resolveMesh(core, meshes + i);
            resolveMaterial(core, meshes + i);
        }
    }
    return R.ok;
}

const testing = std.testing;

const Recorder = struct {
    var mesh_key: [192]u8 = undefined;
    var mesh_key_len: usize = 0;
    var mesh_calls: u32 = 0;
    var vertex_count: usize = 0;
    var index_count: u32 = 0;

    var material_key: [192]u8 = undefined;
    var material_key_len: usize = 0;
    var material_calls: u32 = 0;
    var material_roughness: f32 = 0;
    var material_alpha_mode: abi_render.ke_alpha_mode = 0;

    fn reset() void {
        mesh_key_len = 0;
        mesh_calls = 0;
        vertex_count = 0;
        index_count = 0;
        material_key_len = 0;
        material_calls = 0;
        material_roughness = 0;
        material_alpha_mode = 0;
    }

    fn meshKey() []const u8 {
        return mesh_key[0..mesh_key_len];
    }

    fn materialKey() []const u8 {
        return material_key[0..material_key_len];
    }
};

fn recordUploadMesh(
    _: [*c]abi_render.ke_render_service,
    key: [*c]const u8,
    _: ?*const anyopaque,
    vertices_size: usize,
    _: [*c]const u16,
    idx_count: u32,
    out: [*c]abi_render.ke_mesh_handle,
) callconv(.c) abi_result.ke_result {
    const k = std.mem.span(key);
    @memcpy(Recorder.mesh_key[0..k.len], k);
    Recorder.mesh_key_len = k.len;
    Recorder.vertex_count = vertices_size / @sizeOf(Vertex);
    Recorder.index_count = idx_count;
    Recorder.mesh_calls += 1;
    out.* = .{ .bits = 42 };
    return R.ok;
}

fn recordCreateMaterial(
    _: [*c]abi_render.ke_render_service,
    key: [*c]const u8,
    _: [*c]const f32,
    _: f32,
    roughness: f32,
    _: abi_render.ke_texture_handle,
    _: abi_render.ke_texture_handle,
    alpha_mode: abi_render.ke_alpha_mode,
    _: f32,
    _: f32,
    _: f32,
    _: [*c]const u8,
    out: [*c]abi_render.ke_material_handle,
) callconv(.c) abi_result.ke_result {
    const k = std.mem.span(key);
    @memcpy(Recorder.material_key[0..k.len], k);
    Recorder.material_key_len = k.len;
    Recorder.material_roughness = roughness;
    Recorder.material_alpha_mode = alpha_mode;
    Recorder.material_calls += 1;
    out.* = .{ .bits = 43 };
    return R.ok;
}

fn recordingService() abi_render.ke_render_service {
    var svc = std.mem.zeroes(abi_render.ke_render_service);
    svc.upload_mesh = recordUploadMesh;
    svc.create_material = recordCreateMaterial;
    return svc;
}

fn meshNamed(primitive: []const u8) abi_render.ke_mesh_component {
    var m = std.mem.zeroes(abi_render.ke_mesh_component);
    @memcpy(m.primitive[0..primitive.len], primitive);
    return m;
}

test "the quad primitive uploads four vertices and six indices under its own key" {
    Recorder.reset();
    var svc = recordingService();
    var m = meshNamed("quad");
    resolveMesh(&svc, &m);
    try testing.expectEqualStrings("primitive:quad", Recorder.meshKey());
    try testing.expectEqual(@as(usize, 4), Recorder.vertex_count);
    try testing.expectEqual(@as(u32, 6), Recorder.index_count);
    try testing.expectEqual(@as(u32, 42), m.mesh.bits);
}

test "the plane primitive is a quad lying flat, keyed apart from the upright one" {
    Recorder.reset();
    var svc = recordingService();
    var m = meshNamed("plane");
    resolveMesh(&svc, &m);
    try testing.expectEqualStrings("primitive:plane", Recorder.meshKey());
    try testing.expectEqual(@as(usize, 4), Recorder.vertex_count);
}

test "the cube primitive has four vertices per face so each face keeps its own normal" {
    Recorder.reset();
    var svc = recordingService();
    var m = meshNamed("cube");
    resolveMesh(&svc, &m);
    try testing.expectEqualStrings("primitive:cube", Recorder.meshKey());
    try testing.expectEqual(@as(usize, 24), Recorder.vertex_count);
    try testing.expectEqual(@as(u32, 36), Recorder.index_count);
}

test "the sphere primitive names its own tessellation in its key" {
    Recorder.reset();
    var svc = recordingService();
    var m = meshNamed("sphere");
    resolveMesh(&svc, &m);
    try testing.expectEqualStrings("primitive:sphere:0.5:24:32", Recorder.meshKey());
    try testing.expectEqual(@as(usize, (sphere_rings + 1) * (sphere_segments + 1)), Recorder.vertex_count);
    try testing.expectEqual(@as(u32, sphere_rings * sphere_segments * 6), Recorder.index_count);
}

test "two inline materials differing only in distortion strength get different keys" {
    var svc = recordingService();

    Recorder.reset();
    var calm = meshNamed("quad");
    calm.distortion_strength = 0.0;
    resolveMaterial(&svc, &calm);
    var calm_key: [192]u8 = undefined;
    const calm_len = Recorder.material_key_len;
    @memcpy(calm_key[0..calm_len], Recorder.materialKey());

    Recorder.reset();
    var wavy = meshNamed("quad");
    wavy.distortion_strength = 0.5;
    resolveMaterial(&svc, &wavy);

    try testing.expect(!std.mem.eql(u8, calm_key[0..calm_len], Recorder.materialKey()));
}

test "a primitive nobody implements resolves to no mesh rather than a wrong one" {
    Recorder.reset();
    var svc = recordingService();
    var m = meshNamed("torus");
    resolveMesh(&svc, &m);
    try testing.expectEqual(@as(u32, 0), Recorder.mesh_calls);
    try testing.expectEqual(@as(u32, abi_render.KE_HANDLE_NONE), m.mesh.bits);
}

test "a mesh naming no primitive is left alone" {
    Recorder.reset();
    var svc = recordingService();
    var m = std.mem.zeroes(abi_render.ke_mesh_component);
    resolveMesh(&svc, &m);
    try testing.expectEqual(@as(u32, 0), Recorder.mesh_calls);
}

test "a mesh that already carries a handle is not uploaded again" {
    Recorder.reset();
    var svc = recordingService();
    var m = meshNamed("quad");
    m.mesh = .{ .bits = 5 };
    resolveMesh(&svc, &m);
    try testing.expectEqual(@as(u32, 0), Recorder.mesh_calls);
    try testing.expectEqual(@as(u32, 5), m.mesh.bits);
}

test "a mesh without a material gets one built from the values authored on it" {
    Recorder.reset();
    var svc = recordingService();
    var m = std.mem.zeroes(abi_render.ke_mesh_component);
    m.base_color = .{ .x = 1, .y = 0, .z = 0, .w = 1 };
    m.roughness = 0.25;
    m.alpha_mode = abi_render.KE_ALPHA_MODE_BLEND;
    resolveMaterial(&svc, &m);
    try testing.expectEqual(@as(u32, 1), Recorder.material_calls);
    try testing.expectEqual(@as(f32, 0.25), Recorder.material_roughness);
    try testing.expectEqual(@as(abi_render.ke_alpha_mode, abi_render.KE_ALPHA_MODE_BLEND), Recorder.material_alpha_mode);
    try testing.expectEqual(@as(u32, 43), m.material.bits);
}

test "the material cache key is spelled out of every value that changes the shading" {
    Recorder.reset();
    var svc = recordingService();
    var m = std.mem.zeroes(abi_render.ke_mesh_component);
    m.roughness = 0.25;
    resolveMaterial(&svc, &m);
    var first: [192]u8 = undefined;
    const first_len = Recorder.material_key_len;
    @memcpy(first[0..first_len], Recorder.materialKey());

    var other = std.mem.zeroes(abi_render.ke_mesh_component);
    other.roughness = 0.75;
    resolveMaterial(&svc, &other);
    try testing.expect(!std.mem.eql(u8, first[0..first_len], Recorder.materialKey()));
}

test "a mesh that already carries a material keeps it" {
    Recorder.reset();
    var svc = recordingService();
    var m = std.mem.zeroes(abi_render.ke_mesh_component);
    m.material = .{ .bits = 8 };
    resolveMaterial(&svc, &m);
    try testing.expectEqual(@as(u32, 0), Recorder.material_calls);
    try testing.expectEqual(@as(u32, 8), m.material.bits);
}

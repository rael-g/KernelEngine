const cimport = @import("cimport.zig");
const c = cimport.c;

const std = @import("std");

const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    tangent: [3]f32,
};

fn quad(core: *c.ke_render_service, out_error: [*c][*c]c.ke_error) c.ke_mesh_handle {
    const t = [3]f32{ 1, 0, 0 };
    const verts = [4]Vertex{
        .{ .position = .{ -0.5, -0.5, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 1 }, .tangent = t },
        .{ .position = .{ 0.5, -0.5, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 1, 1 }, .tangent = t },
        .{ .position = .{ 0.5, 0.5, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 1, 0 }, .tangent = t },
        .{ .position = .{ -0.5, 0.5, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 0 }, .tangent = t },
    };
    const idx = [6]u16{ 0, 1, 2, 0, 2, 3 };
    return core.upload_mesh.?(core, "primitive:quad", &verts, @sizeOf(@TypeOf(verts)), &idx, idx.len, out_error);
}

fn plane(core: *c.ke_render_service, out_error: [*c][*c]c.ke_error) c.ke_mesh_handle {
    const n = [3]f32{ 0, 1, 0 };
    const t = [3]f32{ 1, 0, 0 };
    const verts = [4]Vertex{
        .{ .position = .{ -0.5, 0, -0.5 }, .normal = n, .uv = .{ 0, 0 }, .tangent = t },
        .{ .position = .{ 0.5, 0, -0.5 }, .normal = n, .uv = .{ 1, 0 }, .tangent = t },
        .{ .position = .{ 0.5, 0, 0.5 }, .normal = n, .uv = .{ 1, 1 }, .tangent = t },
        .{ .position = .{ -0.5, 0, 0.5 }, .normal = n, .uv = .{ 0, 1 }, .tangent = t },
    };
    const idx = [6]u16{ 0, 1, 2, 0, 2, 3 };
    return core.upload_mesh.?(core, "primitive:plane", &verts, @sizeOf(@TypeOf(verts)), &idx, idx.len, out_error);
}

fn sub(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn normalize(v: [3]f32) [3]f32 {
    const len = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (len < 1e-8) return v;
    return .{ v[0] / len, v[1] / len, v[2] / len };
}

fn cube(core: *c.ke_render_service, out_error: [*c][*c]c.ke_error) c.ke_mesh_handle {
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
    return core.upload_mesh.?(core, "primitive:cube", &verts, @sizeOf(@TypeOf(verts)), &idx, idx.len, out_error);
}

const sphere_rings = 24;
const sphere_segments = 32;

fn uvSphere(core: *c.ke_render_service, out_error: [*c][*c]c.ke_error) c.ke_mesh_handle {
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
    return core.upload_mesh.?(core, "primitive:sphere:0.5:24:32", &verts, @sizeOf(@TypeOf(verts)), &idx, idx.len, out_error);
}

fn resolveMesh(core: *c.ke_render_service, m: [*c]c.ke_mesh_component) void {
    const mc: *c.ke_mesh_component = @ptrCast(m);
    if (c.ke_mesh_is_valid(mc.mesh) or mc.primitive[0] == 0) return;
    const name = std.mem.sliceTo(&mc.primitive, 0);
    mc.mesh = if (std.mem.eql(u8, name, "quad"))
        quad(core, null)
    else if (std.mem.eql(u8, name, "plane"))
        plane(core, null)
    else if (std.mem.eql(u8, name, "cube"))
        cube(core, null)
    else if (std.mem.eql(u8, name, "sphere"))
        uvSphere(core, null)
    else
        c.KE_MESH_NONE;
}

fn resolveMaterial(core: *c.ke_render_service, m: [*c]c.ke_mesh_component) void {
    const mc: *c.ke_mesh_component = @ptrCast(m);
    if (c.ke_material_is_valid(mc.material)) return;
    const bc = mc.base_color;

    var key_buf: [160]u8 = undefined;
    const key = std.fmt.bufPrintZ(
        &key_buf,
        "inline:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}",
        .{ bc.x, bc.y, bc.z, bc.w, mc.roughness, mc.alpha_mode, mc.alpha_cutoff, mc.ior },
    ) catch return;

    mc.material = core.create_material.?(
        core,
        key.ptr,
        @ptrCast(&mc.base_color),
        0,
        mc.roughness,
        c.KE_TEXTURE_NONE,
        c.KE_TEXTURE_NONE,
        mc.alpha_mode,
        mc.alpha_cutoff,
        mc.ior,
        mc.distortion_strength,
        null,
        null,
    );
}

pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const core: *c.ke_render_service = @ptrCast(@alignCast(user.?));

    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const meshes: [*c]c.ke_mesh_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            resolveMesh(core, meshes + i);
            resolveMaterial(core, meshes + i);
        }
    }
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
    var material_alpha_mode: c.ke_alpha_mode = 0;

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
    _: [*c]c.ke_render_service,
    key: [*c]const u8,
    _: ?*const anyopaque,
    vertices_size: usize,
    _: [*c]const u16,
    idx_count: u32,
    _: [*c][*c]c.ke_error,
) callconv(.c) c.ke_mesh_handle {
    const k = std.mem.span(key);
    @memcpy(Recorder.mesh_key[0..k.len], k);
    Recorder.mesh_key_len = k.len;
    Recorder.vertex_count = vertices_size / @sizeOf(Vertex);
    Recorder.index_count = idx_count;
    Recorder.mesh_calls += 1;
    return .{ .bits = 42 };
}

fn recordCreateMaterial(
    _: [*c]c.ke_render_service,
    key: [*c]const u8,
    _: [*c]const f32,
    _: f32,
    roughness: f32,
    _: c.ke_texture_handle,
    _: c.ke_texture_handle,
    alpha_mode: c.ke_alpha_mode,
    _: f32,
    _: f32,
    _: f32,
    _: [*c]const u8,
    _: [*c][*c]c.ke_error,
) callconv(.c) c.ke_material_handle {
    const k = std.mem.span(key);
    @memcpy(Recorder.material_key[0..k.len], k);
    Recorder.material_key_len = k.len;
    Recorder.material_roughness = roughness;
    Recorder.material_alpha_mode = alpha_mode;
    Recorder.material_calls += 1;
    return .{ .bits = 43 };
}

fn recordingService() c.ke_render_service {
    var svc = std.mem.zeroes(c.ke_render_service);
    svc.upload_mesh = recordUploadMesh;
    svc.create_material = recordCreateMaterial;
    return svc;
}

fn meshNamed(primitive: []const u8) c.ke_mesh_component {
    var m = std.mem.zeroes(c.ke_mesh_component);
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

test "a primitive nobody implements resolves to no mesh rather than a wrong one" {
    Recorder.reset();
    var svc = recordingService();
    var m = meshNamed("torus");
    resolveMesh(&svc, &m);
    try testing.expectEqual(@as(u32, 0), Recorder.mesh_calls);
    try testing.expectEqual(@as(u32, c.KE_HANDLE_NONE), m.mesh.bits);
}

test "a mesh naming no primitive is left alone" {
    Recorder.reset();
    var svc = recordingService();
    var m = std.mem.zeroes(c.ke_mesh_component);
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
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.base_color = .{ .x = 1, .y = 0, .z = 0, .w = 1 };
    m.roughness = 0.25;
    m.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    resolveMaterial(&svc, &m);
    try testing.expectEqual(@as(u32, 1), Recorder.material_calls);
    try testing.expectEqual(@as(f32, 0.25), Recorder.material_roughness);
    try testing.expectEqual(@as(c.ke_alpha_mode, c.KE_ALPHA_MODE_BLEND), Recorder.material_alpha_mode);
    try testing.expectEqual(@as(u32, 43), m.material.bits);
}

test "the material cache key is spelled out of every value that changes the shading" {
    Recorder.reset();
    var svc = recordingService();
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.roughness = 0.25;
    resolveMaterial(&svc, &m);
    var first: [192]u8 = undefined;
    const first_len = Recorder.material_key_len;
    @memcpy(first[0..first_len], Recorder.materialKey());

    var other = std.mem.zeroes(c.ke_mesh_component);
    other.roughness = 0.75;
    resolveMaterial(&svc, &other);
    try testing.expect(!std.mem.eql(u8, first[0..first_len], Recorder.materialKey()));
}

test "a mesh that already carries a material keeps it" {
    Recorder.reset();
    var svc = recordingService();
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.material = .{ .bits = 8 };
    resolveMaterial(&svc, &m);
    try testing.expectEqual(@as(u32, 0), Recorder.material_calls);
    try testing.expectEqual(@as(u32, 8), m.material.bits);
}

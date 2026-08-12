// "render.mesh.resolve" — the native system that turns a scene-authored
// ke_mesh_component (a primitive name + material-authoring fields, both plain
// data) into real GPU handles. This is the logic MeshRenderer.cs used to do
// by hand-written C# reaching into IRenderResources/MeshPrimitives; the node
// itself never held any of it — it only ever wrote MeshHandle/MaterialHandle
// straight through. Moving the resolution into a system, not a node, is what
// makes MeshRenderer a pure ECS facade: it writes data, this system (or a
// caller with already-resolved handles) is what gives that data meaning.
//
// Runs every KE_PHASE_UPDATE tick with write access to "mesh", but only acts
// on an entity whose mesh/material handle is still KE_MESH_NONE/
// KE_MATERIAL_NONE — upload_mesh/create_material are both dedup-cached by key,
// so re-checking an already-resolved entity is a cheap validity check, not a
// re-upload.

const cimport = @import("cimport.zig");
const c = cimport.c;

const std = @import("std");

// Matches the forward pipeline's expected vertex stride (11 floats): position
// + normal + uv + tangent. No native ke_mesh_vertex struct exists — upload_mesh
// takes raw bytes by design (a mesh's vertex layout is a pipeline concern, not
// an ABI one) — this is the same layout convention examples/c/14_forward_mesh
// and the C# MeshVertex struct already use.
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

    // No file backs an inline scene-authored color, so the key is the
    // material's own parameters — two entities authored with identical
    // inline values dedup to one material via upload_mesh/create_material's
    // own key-cache.
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
        0, // metallic
        mc.roughness,
        c.KE_TEXTURE_NONE,
        c.KE_TEXTURE_NONE,
        mc.alpha_mode,
        mc.alpha_cutoff,
        mc.ior,
        mc.distortion_strength,
        null, // shader: engine default ("standard")
        null,
    );
}

pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const core: *c.ke_render_service = @alignCast(@ptrCast(user.?));

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

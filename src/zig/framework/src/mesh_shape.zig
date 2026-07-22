// CPU-side primitive mesh baking — pure math. Internal to the framework
// plugin (see mesh_shape_internal.h). External callers reach these through
// ke_asset_resolver->resolve_mesh.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const pi: f32 = 3.14159265358979323846;

// Buffers cross back to C as bare pointers with no length attached. The counts
// travelling on ke_mesh_shape_data are what the free path reconstructs the
// slices from, so a bake must never publish a count that differs from what it
// allocated.
fn allocArray(comptime T: type, count: u32) ?[*]T {
    if (count == 0) return null;
    const slice = heap.gpa.alloc(T, count) catch return null;
    return slice.ptr;
}

fn setVertex(
    v: *c.ke_vertex,
    x: f32,
    y: f32,
    z: f32,
    nx: f32,
    ny: f32,
    nz: f32,
    u: f32,
    vc: f32,
    tx: f32,
    ty: f32,
    tz: f32,
    tw: f32,
) void {
    v.x = x;
    v.y = y;
    v.z = z;
    v.nx = nx;
    v.ny = ny;
    v.nz = nz;
    v.u = u;
    v.v = vc;
    v.tx = tx;
    v.ty = ty;
    v.tz = tz;
    v.tw = tw;
}

const Vec3 = [3]f32;

fn bakeQuadLike(
    vtx: [*]c.ke_vertex,
    idx: [*]u16,
    n: Vec3,
    t: Vec3,
    p0: Vec3,
    p1: Vec3,
    p2: Vec3,
    p3: Vec3,
) void {
    setVertex(&vtx[0], p0[0], p0[1], p0[2], n[0], n[1], n[2], 0, 0, t[0], t[1], t[2], 1);
    setVertex(&vtx[1], p1[0], p1[1], p1[2], n[0], n[1], n[2], 1, 0, t[0], t[1], t[2], 1);
    setVertex(&vtx[2], p2[0], p2[1], p2[2], n[0], n[1], n[2], 1, 1, t[0], t[1], t[2], 1);
    setVertex(&vtx[3], p3[0], p3[1], p3[2], n[0], n[1], n[2], 0, 1, t[0], t[1], t[2], 1);
    idx[0] = 0;
    idx[1] = 1;
    idx[2] = 2;
    idx[3] = 0;
    idx[4] = 2;
    idx[5] = 3;
}

const CubeFace = struct {
    n: Vec3,
    t: Vec3,
    p: [4]Vec3,
};

const cube_faces = [6]CubeFace{
    // +X
    .{ .n = .{ 1, 0, 0 }, .t = .{ 0, 0, -1 }, .p = .{ .{ 0.5, -0.5, 0.5 }, .{ 0.5, -0.5, -0.5 }, .{ 0.5, 0.5, -0.5 }, .{ 0.5, 0.5, 0.5 } } },
    // -X
    .{ .n = .{ -1, 0, 0 }, .t = .{ 0, 0, 1 }, .p = .{ .{ -0.5, -0.5, -0.5 }, .{ -0.5, -0.5, 0.5 }, .{ -0.5, 0.5, 0.5 }, .{ -0.5, 0.5, -0.5 } } },
    // +Y
    .{ .n = .{ 0, 1, 0 }, .t = .{ 1, 0, 0 }, .p = .{ .{ -0.5, 0.5, 0.5 }, .{ 0.5, 0.5, 0.5 }, .{ 0.5, 0.5, -0.5 }, .{ -0.5, 0.5, -0.5 } } },
    // -Y
    .{ .n = .{ 0, -1, 0 }, .t = .{ 1, 0, 0 }, .p = .{ .{ -0.5, -0.5, -0.5 }, .{ 0.5, -0.5, -0.5 }, .{ 0.5, -0.5, 0.5 }, .{ -0.5, -0.5, 0.5 } } },
    // +Z
    .{ .n = .{ 0, 0, 1 }, .t = .{ 1, 0, 0 }, .p = .{ .{ -0.5, -0.5, 0.5 }, .{ 0.5, -0.5, 0.5 }, .{ 0.5, 0.5, 0.5 }, .{ -0.5, 0.5, 0.5 } } },
    // -Z
    .{ .n = .{ 0, 0, -1 }, .t = .{ -1, 0, 0 }, .p = .{ .{ 0.5, -0.5, -0.5 }, .{ -0.5, -0.5, -0.5 }, .{ -0.5, 0.5, -0.5 }, .{ 0.5, 0.5, -0.5 } } },
};

fn bakeCube(vtx: [*]c.ke_vertex, idx: [*]u16) void {
    for (cube_faces, 0..) |face, f| {
        const base: u16 = @intCast(f * 4);
        const uv = [4][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 } };
        for (face.p, uv, 0..) |p, t, k| {
            setVertex(
                &vtx[base + k],
                p[0],
                p[1],
                p[2],
                face.n[0],
                face.n[1],
                face.n[2],
                t[0],
                t[1],
                face.t[0],
                face.t[1],
                face.t[2],
                1,
            );
        }

        const ii = f * 6;
        idx[ii + 0] = base;
        idx[ii + 1] = base + 1;
        idx[ii + 2] = base + 2;
        idx[ii + 3] = base;
        idx[ii + 4] = base + 2;
        idx[ii + 5] = base + 3;
    }
}

fn sphereVertexCount(segments: u32, rings: u32) u32 {
    return (rings + 1) * (segments + 1);
}

fn sphereIndexCount(segments: u32, rings: u32) u32 {
    return rings * segments * 6;
}

fn bakeSphere(vtx: [*]c.ke_vertex, idx: [*]u16, segments: u32, rings: u32) void {
    var v: usize = 0;
    var r: u32 = 0;
    while (r <= rings) : (r += 1) {
        const phi = pi * @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rings));
        const y = @cos(phi);
        const sin_phi = @sin(phi);
        var s: u32 = 0;
        while (s <= segments) : (s += 1) {
            const theta = 2.0 * pi * @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(segments));
            const x = sin_phi * @cos(theta);
            const z = sin_phi * @sin(theta);
            const tx = -@sin(theta);
            const tz = @cos(theta);
            setVertex(
                &vtx[v],
                x * 0.5,
                y * 0.5,
                z * 0.5,
                x,
                y,
                z,
                @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(segments)),
                @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rings)),
                tx,
                0.0,
                tz,
                1.0,
            );
            v += 1;
        }
    }

    var i: usize = 0;
    const row = segments + 1;
    r = 0;
    while (r < rings) : (r += 1) {
        var s: u32 = 0;
        while (s < segments) : (s += 1) {
            const a: u16 = @intCast(r * row + s);
            const b: u16 = @intCast(a + row);
            const cc: u16 = a + 1;
            const d: u16 = b + 1;
            idx[i + 0] = a;
            idx[i + 1] = b;
            idx[i + 2] = cc;
            idx[i + 3] = cc;
            idx[i + 4] = b;
            idx[i + 5] = d;
            i += 6;
        }
    }
}

pub export fn ke_mesh_shape_bake_internal(
    prim: c.ke_mesh_primitive,
    segments_in: u32,
    out_data: ?*c.ke_mesh_shape_data,
) callconv(.c) bool {
    const out = out_data orelse return false;
    out.* = std.mem.zeroes(c.ke_mesh_shape_data);

    var segments = segments_in;
    var rings: u32 = 0;
    var vcount: u32 = 0;
    var icount: u32 = 0;

    switch (prim) {
        c.KE_MESH_PRIMITIVE_QUAD, c.KE_MESH_PRIMITIVE_PLANE => {
            vcount = 4;
            icount = 6;
        },
        c.KE_MESH_PRIMITIVE_CUBE => {
            vcount = 24;
            icount = 36;
        },
        c.KE_MESH_PRIMITIVE_SPHERE => {
            if (segments == 0) segments = 32;
            if (segments < 3) segments = 3;
            rings = segments / 2;
            if (rings < 2) rings = 2;
            vcount = sphereVertexCount(segments, rings);
            icount = sphereIndexCount(segments, rings);
        },
        else => return false,
    }

    const vbuf = allocArray(c.ke_vertex, vcount) orelse return false;
    const ibuf = allocArray(u16, icount) orelse {
        heap.gpa.free(vbuf[0..vcount]);
        return false;
    };

    switch (prim) {
        c.KE_MESH_PRIMITIVE_QUAD => bakeQuadLike(
            vbuf,
            ibuf,
            .{ 0, 0, 1 },
            .{ 1, 0, 0 },
            .{ -0.5, -0.5, 0 },
            .{ 0.5, -0.5, 0 },
            .{ 0.5, 0.5, 0 },
            .{ -0.5, 0.5, 0 },
        ),
        c.KE_MESH_PRIMITIVE_PLANE => bakeQuadLike(
            vbuf,
            ibuf,
            .{ 0, 1, 0 },
            .{ 1, 0, 0 },
            .{ -0.5, 0, 0.5 },
            .{ 0.5, 0, 0.5 },
            .{ 0.5, 0, -0.5 },
            .{ -0.5, 0, -0.5 },
        ),
        c.KE_MESH_PRIMITIVE_CUBE => bakeCube(vbuf, ibuf),
        c.KE_MESH_PRIMITIVE_SPHERE => bakeSphere(vbuf, ibuf, segments, rings),
        else => {
            // Unreachable via the sizing switch above, but a bad enum value must
            // surface as a failed bake rather than a trap.
            heap.gpa.free(vbuf[0..vcount]);
            heap.gpa.free(ibuf[0..icount]);
            return false;
        },
    }

    out.vertices = vbuf;
    out.vertex_count = vcount;
    out.indices = ibuf;
    out.index_count = icount;
    return true;
}

pub export fn ke_mesh_shape_free_internal(data_in: ?*c.ke_mesh_shape_data) callconv(.c) void {
    const data = data_in orelse return;
    if (data.vertices) |v| heap.gpa.free(@as([*]c.ke_vertex, @ptrCast(v))[0..data.vertex_count]);
    if (data.indices) |i| heap.gpa.free(@as([*]u16, @ptrCast(i))[0..data.index_count]);
    data.vertices = null;
    data.indices = null;
    data.vertex_count = 0;
    data.index_count = 0;
}


const c = @import("c.zig").c;

/// Row-major 4x4 multiply: out = a * b. Computed into a temporary so `out` may
/// alias either input.
pub fn mul(out: *c.ke_mat4, a: *const c.ke_mat4, b: *const c.ke_mat4) void {
    var res: [16]f32 = undefined;
    for (0..4) |i| {
        for (0..4) |j| {
            res[i * 4 + j] =
                a.m[i * 4 + 0] * b.m[0 * 4 + j] +
                a.m[i * 4 + 1] * b.m[1 * 4 + j] +
                a.m[i * 4 + 2] * b.m[2 * 4 + j] +
                a.m[i * 4 + 3] * b.m[3 * 4 + j];
        }
    }
    out.m = res;
}

/// Composes translation, rotation (quaternion) and scale into a row-major
/// affine matrix with translation in the last row.
pub fn fromTransform(
    out: *c.ke_mat4,
    pos: *const c.ke_vec3,
    rot: *const c.ke_quat,
    scale: *const c.ke_vec3,
) void {
    const qx = rot.x;
    const qy = rot.y;
    const qz = rot.z;
    const qw = rot.w;

    const r00 = 1.0 - 2.0 * (qy * qy + qz * qz);
    const r01 = 2.0 * (qx * qy + qz * qw);
    const r02 = 2.0 * (qx * qz - qy * qw);
    const r10 = 2.0 * (qx * qy - qz * qw);
    const r11 = 1.0 - 2.0 * (qx * qx + qz * qz);
    const r12 = 2.0 * (qy * qz + qx * qw);
    const r20 = 2.0 * (qx * qz + qy * qw);
    const r21 = 2.0 * (qy * qz - qx * qw);
    const r22 = 1.0 - 2.0 * (qx * qx + qy * qy);

    out.m = .{
        r00 * scale.x, r01 * scale.x, r02 * scale.x, 0.0,
        r10 * scale.y, r11 * scale.y, r12 * scale.y, 0.0,
        r20 * scale.z, r21 * scale.z, r22 * scale.z, 0.0,
        pos.x,         pos.y,         pos.z,         1.0,
    };
}

/// Composes a 2D pose into the same row-major affine matrix a 3D one produces:
/// rotation is about Z, and depth is the Z the plane sits at.
pub fn fromTransform2d(
    out: *c.ke_mat4,
    pos: *const c.ke_vec2,
    rotation: f32,
    scale: *const c.ke_vec2,
    depth: f32,
) void {
    const cs = @cos(rotation);
    const sn = @sin(rotation);

    out.m = .{
        cs * scale.x,  sn * scale.x, 0.0,   0.0,
        -sn * scale.y, cs * scale.y, 0.0,   0.0,
        0.0,           0.0,          1.0,   0.0,
        pos.x,         pos.y,        depth, 1.0,
    };
}

const std = @import("std");

test "a 2d pose lands in the same row-major layout a 3d one produces" {
    var m: c.ke_mat4 = undefined;
    const pos = c.ke_vec2{ .x = 3.0, .y = 4.0 };
    const scale = c.ke_vec2{ .x = 1.0, .y = 1.0 };
    fromTransform2d(&m, &pos, 0.0, &scale, 7.0);

    try std.testing.expectEqual(@as(f32, 3.0), m.m[12]);
    try std.testing.expectEqual(@as(f32, 4.0), m.m[13]);
    try std.testing.expectEqual(@as(f32, 7.0), m.m[14]);
    try std.testing.expectEqual(@as(f32, 1.0), m.m[15]);
}

test "a quarter turn in 2d maps x onto y, the same sense a z quaternion does" {
    const half = @sqrt(2.0) / 2.0;
    var flat: c.ke_mat4 = undefined;
    const pos2 = c.ke_vec2{ .x = 0.0, .y = 0.0 };
    const scale2 = c.ke_vec2{ .x = 1.0, .y = 1.0 };
    fromTransform2d(&flat, &pos2, std.math.pi / 2.0, &scale2, 0.0);

    var spatial: c.ke_mat4 = undefined;
    const pos3 = c.ke_vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const rot = c.ke_quat{ .x = 0.0, .y = 0.0, .z = half, .w = half };
    const scale3 = c.ke_vec3{ .x = 1.0, .y = 1.0, .z = 1.0 };
    fromTransform(&spatial, &pos3, &rot, &scale3);

    for (0..16) |i| try std.testing.expectApproxEqAbs(spatial.m[i], flat.m[i], 1e-6);
}

test "2d scale reaches only the plane, leaving depth unscaled" {
    var m: c.ke_mat4 = undefined;
    const pos = c.ke_vec2{ .x = 0.0, .y = 0.0 };
    const scale = c.ke_vec2{ .x = 2.0, .y = 3.0 };
    fromTransform2d(&m, &pos, 0.0, &scale, 0.0);

    try std.testing.expectEqual(@as(f32, 2.0), m.m[0]);
    try std.testing.expectEqual(@as(f32, 3.0), m.m[5]);
    try std.testing.expectEqual(@as(f32, 1.0), m.m[10]);
}

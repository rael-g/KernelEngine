// Zig ports of the matrix helpers that live as `static inline` in
// kernel_engine/common/math.h.
//
// translate-c cannot lower those bodies (nested array indexing inside the
// index expression), and being `static inline` they export no symbol to link
// against — so Zig callers need their own copy. Any change to the C originals
// must be mirrored here; the shared regression is scene-tree transform
// propagation, which compares against hand-computed matrices.

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

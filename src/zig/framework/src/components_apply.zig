// Per-component apply callback for the framework's own component vocabulary —
// just "transform" (scene_tree's, so framework's to own). Every other domain
// registers its own cid + apply callback against ke_world from its own
// plugin (e.g. render's camera/mesh/lights: see
// src/zig/render/service/src/component_apply.zig), via world->register_component_apply.
//
// Conventions:
//   - Field name matching is case-sensitive and exact ("color" != "Color").
//   - Type mismatches are silently skipped (loader semantics: unknown <-> ignore).
//   - Vec arrays from TOML come pre-converted to KE_VARIANT_VEC2/VEC3/VEC4 by
//     the scene_loader's toml->variant pass. A 3-element array becomes VEC3;
//     applies decide whether they want VEC3 or VEC4.

const std = @import("std");

const c = @import("c.zig").c;

const pi: f32 = 3.14159265358979323846;

/// Entries arrive as a C pointer + count; the callbacks only ever read them.
fn entries(e: [*c]const c.ke_variant_table_entry, n: u32) []const c.ke_variant_table_entry {
    if (n == 0) return &.{};
    return e[0..n];
}

fn keyIs(entry: *const c.ke_variant_table_entry, name: []const u8) bool {
    if (entry.key == null) return false;
    return std.mem.eql(u8, std.mem.span(entry.key), name);
}

// Euler ZYX intrinsic, degrees in -> quaternion. Matches C# SceneLoader's
// CreateFromYawPitchRoll(yaw=y, pitch=x, roll=z).
fn eulerDegToQuat(dx: f32, dy: f32, dz: f32) c.ke_quat {
    const k = pi / 180.0 * 0.5;
    const x = dx * k;
    const y = dy * k;
    const z = dz * k;
    const cx = @cos(x);
    const sx = @sin(x);
    const cy = @cos(y);
    const sy = @sin(y);
    const cz = @cos(z);
    const sz = @sin(z);
    return .{
        .x = sx * cy * cz - cx * sy * sz,
        .y = cx * sy * cz + sx * cy * sz,
        .z = cx * cy * sz - sx * sy * cz,
        .w = cx * cy * cz + sx * sy * sz,
    };
}

fn asFloat(v: *const c.ke_variant) ?f32 {
    return switch (v.type) {
        c.KE_VARIANT_FLOAT => @floatCast(v.unnamed_0.f),
        c.KE_VARIANT_INT => @floatFromInt(v.unnamed_0.i),
        else => null,
    };
}

// -- transform ---------------------------------------------------------------

pub export fn ke_framework_apply_transform(ptr: ?*anyopaque, e: [*c]const c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const t: *c.ke_transform_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        const v = &entry.value;
        if (keyIs(entry, "position")) {
            if (v.type == c.KE_VARIANT_VEC3) {
                t.position = v.unnamed_0.v3;
            } else if (v.type == c.KE_VARIANT_VEC2) {
                t.position = .{ .x = v.unnamed_0.v2.x, .y = v.unnamed_0.v2.y, .z = 0 };
            }
        } else if (keyIs(entry, "scale")) {
            if (v.type == c.KE_VARIANT_VEC3) {
                t.scale = v.unnamed_0.v3;
            } else if (v.type == c.KE_VARIANT_VEC2) {
                t.scale = .{ .x = v.unnamed_0.v2.x, .y = v.unnamed_0.v2.y, .z = 1 };
            }
        } else if (keyIs(entry, "rotation")) {
            if (v.type == c.KE_VARIANT_VEC4) {
                t.rotation = .{ .x = v.unnamed_0.v4.x, .y = v.unnamed_0.v4.y, .z = v.unnamed_0.v4.z, .w = v.unnamed_0.v4.w };
            } else if (v.type == c.KE_VARIANT_QUAT) {
                t.rotation = v.unnamed_0.q;
            }
        } else if (keyIs(entry, "rotation_euler")) {
            if (v.type == c.KE_VARIANT_VEC3) {
                t.rotation = eulerDegToQuat(v.unnamed_0.v3.x, v.unnamed_0.v3.y, v.unnamed_0.v3.z);
            }
        }
    }
}

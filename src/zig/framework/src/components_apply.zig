// What the generated ke_component_field table in
// kernel_engine/spatial/component_fields.h cannot express for "transform", the
// only component the framework itself owns. Position, rotation and scale are
// plain fields the table describes and the loader applies before this runs; two
// keys are left, and neither is a value written at an offset.

const std = @import("std");

const c = @import("c.zig").c;

const pi: f32 = 3.14159265358979323846;

/// Entries arrive as a C pointer + count; the callbacks only ever read them.
fn entries(e: [*c]c.ke_variant_table_entry, n: u32) []c.ke_variant_table_entry {
    if (n == 0) return &.{};
    return e[0..n];
}

/// Marks the entry as taken on a match: asking whether a key is yours and being
/// told yes is what claiming it means, and the loader reads that back to find the
/// keys nothing in the engine wanted.
fn keyIs(entry: *c.ke_variant_table_entry, name: []const u8) bool {
    if (entry.key == null) return false;
    if (!std.mem.eql(u8, std.mem.span(entry.key), name)) return false;
    entry.consumed = true;
    return true;
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

/// A 2D pose stores radians, and a scene authors degrees — the same unit it
/// authors 3D rotation in. A description maps a key to storage and cannot say
/// "and convert", so the conversion lands here.
pub export fn ke_framework_apply_transform2d(ptr: ?*anyopaque, e: [*c]c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const t: *c.ke_transform2d_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "rotation")) continue;
        t.rotation = t.rotation * (pi / 180.0);
    }
}

/// Two corrections the table cannot make:
///
/// `rotation_euler` is three angles standing for the same quaternion `rotation`
/// holds — a description maps a key to storage and cannot say "and convert".
///
/// A 2D `scale` widens to z=0 through the generic path, which is the right fill
/// for a position and collapses an object flat here. A scale authored in 2D
/// means "leave depth alone", so z returns to 1.
pub export fn ke_framework_apply_transform(ptr: ?*anyopaque, e: [*c]c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const t: *c.ke_transform_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        const v = &entry.value;
        if (keyIs(entry, "rotation_euler")) {
            if (v.type == c.KE_VARIANT_VEC3)
                t.rotation = eulerDegToQuat(v.unnamed_0.v3.x, v.unnamed_0.v3.y, v.unnamed_0.v3.z);
        } else if (keyIs(entry, "scale") and v.type == c.KE_VARIANT_VEC2) {
            t.scale.z = 1;
        }
    }
}

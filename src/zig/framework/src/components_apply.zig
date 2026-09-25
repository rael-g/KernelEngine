
const std = @import("std");

const c = @import("c.zig").c;

const E = @import("kerror").Errors(c);

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

fn isNumber(v: *const c.ke_variant) bool {
    return v.type == c.KE_VARIANT_FLOAT or v.type == c.KE_VARIANT_INT;
}

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
pub export fn ke_framework_apply_transform2d(
    _: ?*anyopaque,
    ptr: ?*anyopaque,
    e: [*c]c.ke_variant_table_entry,
    n: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const t: *c.ke_transform2d_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "rotation")) continue;
        if (!isNumber(&entry.value)) {
            E.fail(out_error, .invalid_argument, "transform2d rotation needs a number of degrees", @src());
            return false;
        }
        t.rotation = t.rotation * (pi / 180.0);
    }
    return true;
}

/// Two corrections the table cannot make:
///
/// `rotation_euler` is three angles standing for the same quaternion `rotation`
/// holds — a description maps a key to storage and cannot say "and convert".
///
/// A 2D `scale` widens to z=0 through the generic path, which is the right fill
/// for a position and collapses an object flat here. A scale authored in 2D
/// means "leave depth alone", so z returns to 1.
pub export fn ke_framework_apply_transform(
    _: ?*anyopaque,
    ptr: ?*anyopaque,
    e: [*c]c.ke_variant_table_entry,
    n: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const t: *c.ke_transform_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        const v = &entry.value;
        if (keyIs(entry, "rotation_euler")) {
            if (v.type != c.KE_VARIANT_VEC3) {
                E.fail(out_error, .invalid_argument, "rotation_euler needs three angles in degrees", @src());
                return false;
            }
            t.rotation = eulerDegToQuat(v.unnamed_0.v3.x, v.unnamed_0.v3.y, v.unnamed_0.v3.z);
        } else if (keyIs(entry, "scale") and v.type == c.KE_VARIANT_VEC2) {
            t.scale.z = 1;
        }
    }
    return true;
}

const testing = std.testing;

fn keyed(key: [*c]const u8, value: c.ke_variant) c.ke_variant_table_entry {
    var e = std.mem.zeroes(c.ke_variant_table_entry);
    e.key = key;
    e.value = value;
    return e;
}

fn vFloat(f: f64) c.ke_variant {
    return .{ .type = c.KE_VARIANT_FLOAT, .unnamed_0 = .{ .f = f } };
}

fn vVec3(x: f32, y: f32, z: f32) c.ke_variant {
    return .{ .type = c.KE_VARIANT_VEC3, .unnamed_0 = .{ .v3 = .{ .x = x, .y = y, .z = z } } };
}

fn vVec2(x: f32, y: f32) c.ke_variant {
    return .{ .type = c.KE_VARIANT_VEC2, .unnamed_0 = .{ .v2 = .{ .x = x, .y = y } } };
}

fn vString(s: [*c]const u8) c.ke_variant {
    return .{ .type = c.KE_VARIANT_STRING, .unnamed_0 = .{ .s = s } };
}

test "a 2D rotation authored in degrees is turned into the radians the pose stores" {
    var t = std.mem.zeroes(c.ke_transform2d_component);
    t.rotation = 180;
    var list = [_]c.ke_variant_table_entry{keyed("rotation", vFloat(180))};
    try testing.expect(ke_framework_apply_transform2d(null, &t, &list, @intCast(list.len), null));
    try testing.expectApproxEqAbs(@as(f32, pi), t.rotation, 1e-6);
    try testing.expect(list[0].consumed);
}

test "a 2D rotation authored as a string fails rather than scaling whatever was there" {
    var t = std.mem.zeroes(c.ke_transform2d_component);
    t.rotation = 90;
    var list = [_]c.ke_variant_table_entry{keyed("rotation", vString("sideways"))};
    try testing.expect(!ke_framework_apply_transform2d(null, &t, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(f32, 90), t.rotation);
}

test "a key the 2D pose does not claim is left for the generic table" {
    var t = std.mem.zeroes(c.ke_transform2d_component);
    var list = [_]c.ke_variant_table_entry{keyed("position", vVec2(1, 2))};
    try testing.expect(ke_framework_apply_transform2d(null, &t, &list, @intCast(list.len), null));
    try testing.expect(!list[0].consumed);
}

test "three euler angles become the quaternion the transform stores" {
    var t = std.mem.zeroes(c.ke_transform_component);
    var list = [_]c.ke_variant_table_entry{keyed("rotation_euler", vVec3(0, 90, 0))};
    try testing.expect(ke_framework_apply_transform(null, &t, &list, @intCast(list.len), null));
    const half_sqrt2: f32 = @sqrt(2.0) / 2.0;
    try testing.expectApproxEqAbs(half_sqrt2, t.rotation.y, 1e-6);
    try testing.expectApproxEqAbs(half_sqrt2, t.rotation.w, 1e-6);
}

test "euler angles authored as anything but three numbers fail the load" {
    var t = std.mem.zeroes(c.ke_transform_component);
    t.rotation = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    var list = [_]c.ke_variant_table_entry{keyed("rotation_euler", vFloat(90))};
    try testing.expect(!ke_framework_apply_transform(null, &t, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(f32, 1), t.rotation.w);
}

test "a scale authored in two dimensions leaves depth alone instead of flattening it" {
    var t = std.mem.zeroes(c.ke_transform_component);
    t.scale = .{ .x = 2, .y = 3, .z = 0 };
    var list = [_]c.ke_variant_table_entry{keyed("scale", vVec2(2, 3))};
    try testing.expect(ke_framework_apply_transform(null, &t, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(f32, 1), t.scale.z);
}

test "a scale authored in three dimensions is left exactly as the table wrote it" {
    var t = std.mem.zeroes(c.ke_transform_component);
    t.scale = .{ .x = 2, .y = 3, .z = 4 };
    var list = [_]c.ke_variant_table_entry{keyed("scale", vVec3(2, 3, 4))};
    try testing.expect(ke_framework_apply_transform(null, &t, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(f32, 4), t.scale.z);
}

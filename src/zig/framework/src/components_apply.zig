//! The table appliers of the two transform components, for the authored keys whose stored form
//! differs from the authored one.

const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_math = @import("abi_math");
const abi_result = @import("abi_result");
const abi_spatial = @import("abi_spatial");

const R = @import("result").Result(abi_result, .{});
const log = std.log.scoped(.framework);

const pi: f32 = 3.14159265358979323846;

fn entries(e: [*c]abi_ecs.ke_variant_table_entry, n: u32) []abi_ecs.ke_variant_table_entry {
    if (n == 0) return &.{};
    return e[0..n];
}

/// Marks the entry consumed whenever its key matches, even if the caller then refuses its value,
/// so a claimed key never reaches the generic writer.
fn keyIs(entry: *abi_ecs.ke_variant_table_entry, name: []const u8) bool {
    if (entry.key == null) return false;
    if (!std.mem.eql(u8, std.mem.span(entry.key.?), name)) return false;
    entry.consumed = true;
    return true;
}

fn isNumber(v: *const abi_ecs.ke_variant) bool {
    return v.type == abi_ecs.KE_VARIANT_FLOAT or v.type == abi_ecs.KE_VARIANT_INT;
}

/// Composes the three axis rotations from angles in degrees into one unit quaternion.
fn eulerDegToQuat(dx: f32, dy: f32, dz: f32) abi_math.ke_quat {
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

/// Table applier of the 2D transform component. It runs after the generic field writer has stored
/// the authored number in the rotation, and converts that stored value from degrees to radians in
/// place. A "rotation" entry that is not a number fails as an invalid argument, logging why;
/// every entry whose key it does not claim stays unconsumed.
pub fn ke_framework_apply_transform2d(
    _: ?*anyopaque,
    ptr: ?*anyopaque,
    e: [*c]abi_ecs.ke_variant_table_entry,
    n: u32,
) callconv(.c) abi_result.ke_result {
    const t: *abi_spatial.ke_transform2d_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "rotation")) continue;
        if (!isNumber(&entry.value)) {
            log.warn("transform2d rotation needs a number of degrees", .{});
            return R.code(error.InvalidArgument);
        }
        t.rotation = t.rotation * (pi / 180.0);
    }
    return R.ok;
}

/// Table applier of the 3D transform component. Once it succeeds, "rotation_euler" has
/// replaced the stored rotation and a two-component "scale" has a depth scale of one, which the
/// generic writer would leave at zero. A "rotation_euler" entry that is not a three-component
/// vector fails as an invalid argument, logging why; every entry whose key it does not claim
/// stays unconsumed.
pub fn ke_framework_apply_transform(
    _: ?*anyopaque,
    ptr: ?*anyopaque,
    e: [*c]abi_ecs.ke_variant_table_entry,
    n: u32,
) callconv(.c) abi_result.ke_result {
    const t: *abi_spatial.ke_transform_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        const v = &entry.value;
        if (keyIs(entry, "rotation_euler")) {
            if (v.type != abi_ecs.KE_VARIANT_VEC3) {
                log.warn("rotation_euler needs three angles in degrees", .{});
                return R.code(error.InvalidArgument);
            }
            t.rotation = eulerDegToQuat(v.unnamed_0.v3.x, v.unnamed_0.v3.y, v.unnamed_0.v3.z);
        } else if (keyIs(entry, "scale") and v.type == abi_ecs.KE_VARIANT_VEC2) {
            t.scale.z = 1;
        }
    }
    return R.ok;
}

const testing = std.testing;

fn keyed(key: [*c]const u8, value: abi_ecs.ke_variant) abi_ecs.ke_variant_table_entry {
    var e = std.mem.zeroes(abi_ecs.ke_variant_table_entry);
    e.key = key;
    e.value = value;
    return e;
}

fn vFloat(f: f64) abi_ecs.ke_variant {
    return .{ .type = abi_ecs.KE_VARIANT_FLOAT, .unnamed_0 = .{ .f = f } };
}

fn vVec3(x: f32, y: f32, z: f32) abi_ecs.ke_variant {
    return .{ .type = abi_ecs.KE_VARIANT_VEC3, .unnamed_0 = .{ .v3 = .{ .x = x, .y = y, .z = z } } };
}

fn vVec2(x: f32, y: f32) abi_ecs.ke_variant {
    return .{ .type = abi_ecs.KE_VARIANT_VEC2, .unnamed_0 = .{ .v2 = .{ .x = x, .y = y } } };
}

fn vString(s: [*c]const u8) abi_ecs.ke_variant {
    return .{ .type = abi_ecs.KE_VARIANT_STRING, .unnamed_0 = .{ .s = s } };
}

test "a 2D rotation authored in degrees is turned into the radians the pose stores" {
    var t = std.mem.zeroes(abi_spatial.ke_transform2d_component);
    t.rotation = 180;
    var list = [_]abi_ecs.ke_variant_table_entry{keyed("rotation", vFloat(180))};
    try testing.expectEqual(R.ok, ke_framework_apply_transform2d(null, &t, &list, @intCast(list.len)));
    try testing.expectApproxEqAbs(@as(f32, pi), t.rotation, 1e-6);
    try testing.expect(list[0].consumed);
}

test "a 2D rotation authored as a string fails rather than scaling whatever was there" {
    var t = std.mem.zeroes(abi_spatial.ke_transform2d_component);
    t.rotation = 90;
    var list = [_]abi_ecs.ke_variant_table_entry{keyed("rotation", vString("sideways"))};
    try testing.expectEqual(R.code(error.InvalidArgument), ke_framework_apply_transform2d(null, &t, &list, @intCast(list.len)));
    try testing.expectEqual(@as(f32, 90), t.rotation);
}

test "a key the 2D pose does not claim is left for the generic table" {
    var t = std.mem.zeroes(abi_spatial.ke_transform2d_component);
    var list = [_]abi_ecs.ke_variant_table_entry{keyed("position", vVec2(1, 2))};
    try testing.expectEqual(R.ok, ke_framework_apply_transform2d(null, &t, &list, @intCast(list.len)));
    try testing.expect(!list[0].consumed);
}

test "three euler angles become the quaternion the transform stores" {
    var t = std.mem.zeroes(abi_spatial.ke_transform_component);
    var list = [_]abi_ecs.ke_variant_table_entry{keyed("rotation_euler", vVec3(0, 90, 0))};
    try testing.expectEqual(R.ok, ke_framework_apply_transform(null, &t, &list, @intCast(list.len)));
    const half_sqrt2: f32 = @sqrt(2.0) / 2.0;
    try testing.expectApproxEqAbs(half_sqrt2, t.rotation.y, 1e-6);
    try testing.expectApproxEqAbs(half_sqrt2, t.rotation.w, 1e-6);
}

test "euler angles authored as anything but three numbers fail the load" {
    var t = std.mem.zeroes(abi_spatial.ke_transform_component);
    t.rotation = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    var list = [_]abi_ecs.ke_variant_table_entry{keyed("rotation_euler", vFloat(90))};
    try testing.expectEqual(R.code(error.InvalidArgument), ke_framework_apply_transform(null, &t, &list, @intCast(list.len)));
    try testing.expectEqual(@as(f32, 1), t.rotation.w);
}

test "a scale authored in two dimensions leaves depth alone instead of flattening it" {
    var t = std.mem.zeroes(abi_spatial.ke_transform_component);
    t.scale = .{ .x = 2, .y = 3, .z = 0 };
    var list = [_]abi_ecs.ke_variant_table_entry{keyed("scale", vVec2(2, 3))};
    try testing.expectEqual(R.ok, ke_framework_apply_transform(null, &t, &list, @intCast(list.len)));
    try testing.expectEqual(@as(f32, 1), t.scale.z);
}

test "a scale authored in three dimensions is left exactly as the table wrote it" {
    var t = std.mem.zeroes(abi_spatial.ke_transform_component);
    t.scale = .{ .x = 2, .y = 3, .z = 4 };
    var list = [_]abi_ecs.ke_variant_table_entry{keyed("scale", vVec3(2, 3, 4))};
    try testing.expectEqual(R.ok, ke_framework_apply_transform(null, &t, &list, @intCast(list.len)));
    try testing.expectEqual(@as(f32, 4), t.scale.z);
}

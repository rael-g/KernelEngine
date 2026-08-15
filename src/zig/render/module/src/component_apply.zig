const std = @import("std");

const c = @import("cimport.zig").c;

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

fn asFloat(v: *const c.ke_variant) ?f32 {
    return switch (v.type) {
        c.KE_VARIANT_FLOAT => @floatCast(v.unnamed_0.f),
        c.KE_VARIANT_INT => @floatFromInt(v.unnamed_0.i),
        else => null,
    };
}

/// `fov_degrees` is the same field as `fov` in a different unit. A table maps a
/// key to storage; it has no way to say "and multiply by pi/180".
pub export fn ke_render_apply_camera(ptr: ?*anyopaque, e: [*c]c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const cam: *c.ke_camera_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "fov_degrees")) continue;
        if (asFloat(&entry.value)) |f| cam.fov = f * (pi / 180.0);
    }
}

fn alphaModeOf(v: *const c.ke_variant) ?u32 {
    if (v.type != c.KE_VARIANT_STRING or v.unnamed_0.s == null) return null;
    const mode = std.mem.span(v.unnamed_0.s);
    if (std.mem.eql(u8, mode, "mask")) return c.KE_ALPHA_MODE_MASK;
    if (std.mem.eql(u8, mode, "blend")) return c.KE_ALPHA_MODE_BLEND;
    return c.KE_ALPHA_MODE_OPAQUE;
}

/// `alpha_mode` is authored as the enumerator's name rather than its number.
/// The table would write the string's bytes over a uint32_t; naming an
/// enumerator is a mapping only the domain that declares the enum holds.
pub export fn ke_render_apply_mesh(ptr: ?*anyopaque, e: [*c]c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const m: *c.ke_mesh_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "alpha_mode")) continue;
        if (alphaModeOf(&entry.value)) |mode| m.alpha_mode = mode;
    }
}

/// Same enumerator-by-name mapping as a mesh's, for the same reason.
pub export fn ke_render_apply_sprite2d(ptr: ?*anyopaque, e: [*c]c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const sp: *c.ke_sprite2d_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "alpha_mode")) continue;
        if (alphaModeOf(&entry.value)) |mode| sp.alpha_mode = mode;
    }
}

const testing = std.testing;

fn vFloat(f: f64) c.ke_variant {
    return .{ .type = c.KE_VARIANT_FLOAT, .unnamed_0 = .{ .f = f } };
}

fn vInt(i: i64) c.ke_variant {
    return .{ .type = c.KE_VARIANT_INT, .unnamed_0 = .{ .i = i } };
}

fn vString(s: [*c]const u8) c.ke_variant {
    return .{ .type = c.KE_VARIANT_STRING, .unnamed_0 = .{ .s = s } };
}

fn keyed(key: [*c]const u8, value: c.ke_variant) c.ke_variant_table_entry {
    var e = std.mem.zeroes(c.ke_variant_table_entry);
    e.key = key;
    e.value = value;
    return e;
}

test "a field of view authored in degrees reaches the component in radians" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vFloat(90.0))};
    ke_render_apply_camera(&cam, &list, @intCast(list.len));
    try testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), cam.fov, 1e-6);
}

test "a field of view authored as a whole number of degrees is coerced, not ignored" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vInt(60))};
    ke_render_apply_camera(&cam, &list, @intCast(list.len));
    try testing.expectApproxEqAbs(@as(f32, std.math.pi / 3.0), cam.fov, 1e-6);
}

test "claiming the field of view key marks it consumed so the loader stops calling it unknown" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vFloat(45.0))};
    ke_render_apply_camera(&cam, &list, @intCast(list.len));
    try testing.expect(list[0].consumed);
}

test "a key the camera does not know is left unconsumed for someone else" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov", vFloat(45.0))};
    ke_render_apply_camera(&cam, &list, @intCast(list.len));
    try testing.expect(!list[0].consumed);
    try testing.expectEqual(@as(f32, 0), cam.fov);
}

test "a field of view authored as a string is claimed but leaves the component untouched" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    cam.fov = 1.25;
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vString("wide"))};
    ke_render_apply_camera(&cam, &list, @intCast(list.len));
    try testing.expect(list[0].consumed);
    try testing.expectEqual(@as(f32, 1.25), cam.fov);
}

test "the last field of view authored for a duplicated key wins" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{
        keyed("fov_degrees", vFloat(30.0)),
        keyed("fov_degrees", vFloat(90.0)),
    };
    ke_render_apply_camera(&cam, &list, @intCast(list.len));
    try testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), cam.fov, 1e-6);
}

test "an empty entry list leaves the camera alone" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    cam.fov = 2.0;
    ke_render_apply_camera(&cam, null, 0);
    try testing.expectEqual(@as(f32, 2.0), cam.fov);
}

test "an entry with no key at all is skipped rather than dereferenced" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed(null, vFloat(90.0))};
    ke_render_apply_camera(&cam, &list, @intCast(list.len));
    try testing.expect(!list[0].consumed);
    try testing.expectEqual(@as(f32, 0), cam.fov);
}

test "a mesh alpha mode authored as mask becomes the mask enumerator" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("mask"))};
    ke_render_apply_mesh(&m, &list, @intCast(list.len));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_MASK), m.alpha_mode);
    try testing.expect(list[0].consumed);
}

test "a mesh alpha mode authored as blend becomes the blend enumerator" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("blend"))};
    ke_render_apply_mesh(&m, &list, @intCast(list.len));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_BLEND), m.alpha_mode);
}

test "a mesh alpha mode authored as opaque becomes the opaque enumerator" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("opaque"))};
    ke_render_apply_mesh(&m, &list, @intCast(list.len));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_OPAQUE), m.alpha_mode);
}

test "a misspelled mesh alpha mode silently becomes opaque instead of failing the load" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("blnd"))};
    ke_render_apply_mesh(&m, &list, @intCast(list.len));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_OPAQUE), m.alpha_mode);
    try testing.expect(list[0].consumed);
}

test "a mesh alpha mode authored as a number is claimed but never written" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vInt(1))};
    ke_render_apply_mesh(&m, &list, @intCast(list.len));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_BLEND), m.alpha_mode);
    try testing.expect(list[0].consumed);
}

test "a mesh alpha mode authored as a null string leaves the component untouched" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString(null))};
    ke_render_apply_mesh(&m, &list, @intCast(list.len));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_BLEND), m.alpha_mode);
}

test "a key the mesh does not know is left unconsumed" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    var list = [_]c.ke_variant_table_entry{keyed("alphamode", vString("blend"))};
    ke_render_apply_mesh(&m, &list, @intCast(list.len));
    try testing.expect(!list[0].consumed);
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_OPAQUE), m.alpha_mode);
}

test "a sprite alpha mode authored as blend becomes the blend enumerator" {
    var sp = std.mem.zeroes(c.ke_sprite2d_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("blend"))};
    ke_render_apply_sprite2d(&sp, &list, @intCast(list.len));
    try testing.expectEqual(@as(@TypeOf(sp.alpha_mode), c.KE_ALPHA_MODE_BLEND), sp.alpha_mode);
    try testing.expect(list[0].consumed);
}

test "a sprite alpha mode authored as mask becomes the mask enumerator" {
    var sp = std.mem.zeroes(c.ke_sprite2d_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("mask"))};
    ke_render_apply_sprite2d(&sp, &list, @intCast(list.len));
    try testing.expectEqual(@as(@TypeOf(sp.alpha_mode), c.KE_ALPHA_MODE_MASK), sp.alpha_mode);
}

test "a misspelled sprite alpha mode silently becomes opaque, matching a mesh" {
    var sp = std.mem.zeroes(c.ke_sprite2d_component);
    sp.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("transparent"))};
    ke_render_apply_sprite2d(&sp, &list, @intCast(list.len));
    try testing.expectEqual(@as(@TypeOf(sp.alpha_mode), c.KE_ALPHA_MODE_OPAQUE), sp.alpha_mode);
}

test "a sprite leaves every key it does not claim for the rest of the engine" {
    var sp = std.mem.zeroes(c.ke_sprite2d_component);
    var list = [_]c.ke_variant_table_entry{
        keyed("fov_degrees", vFloat(90)),
        keyed("alpha_mode", vString("mask")),
        keyed("texture", vString("res://sprite.png")),
    };
    ke_render_apply_sprite2d(&sp, &list, @intCast(list.len));
    try testing.expect(!list[0].consumed);
    try testing.expect(list[1].consumed);
    try testing.expect(!list[2].consumed);
}

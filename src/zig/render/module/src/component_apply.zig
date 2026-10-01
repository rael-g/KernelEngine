const std = @import("std");

const c = @import("cimport.zig").c;
const E = @import("kerror").Errors(c);

const pi: f32 = 3.14159265358979323846;

fn entries(e: [*c]c.ke_variant_table_entry, n: u32) []c.ke_variant_table_entry {
    if (n == 0) return &.{};
    return e[0..n];
}

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

pub export fn ke_render_apply_camera(
    _: ?*anyopaque,
    ptr: ?*anyopaque,
    e: [*c]c.ke_variant_table_entry,
    n: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const cam: *c.ke_camera_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "fov_degrees")) continue;
        const f = asFloat(&entry.value) orelse {
            E.fail(out_error, .invalid_argument, "fov_degrees needs a number of degrees", @src());
            return false;
        };
        if (!(f > 0.0 and f < 180.0)) {
            E.fail(out_error, .invalid_argument, "fov_degrees is an angle strictly between 0 and 180", @src());
            return false;
        }
        cam.fov = f * (pi / 180.0);
    }
    return true;
}

fn alphaModeOf(v: *const c.ke_variant) ?u32 {
    if (v.type != c.KE_VARIANT_STRING or v.unnamed_0.s == null) return null;
    const mode = std.mem.span(v.unnamed_0.s);
    if (std.mem.eql(u8, mode, "mask")) return c.KE_ALPHA_MODE_MASK;
    if (std.mem.eql(u8, mode, "blend")) return c.KE_ALPHA_MODE_BLEND;
    if (std.mem.eql(u8, mode, "opaque")) return c.KE_ALPHA_MODE_OPAQUE;
    return null;
}

pub export fn ke_render_apply_mesh(
    _: ?*anyopaque,
    ptr: ?*anyopaque,
    e: [*c]c.ke_variant_table_entry,
    n: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const m: *c.ke_mesh_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "alpha_mode")) continue;
        m.alpha_mode = alphaModeOf(&entry.value) orelse {
            E.fail(out_error, .invalid_argument, "alpha_mode is one of 'opaque', 'mask' or 'blend'", @src());
            return false;
        };
    }
    return true;
}

pub export fn ke_render_apply_sprite2d(
    _: ?*anyopaque,
    ptr: ?*anyopaque,
    e: [*c]c.ke_variant_table_entry,
    n: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const sp: *c.ke_sprite2d_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "alpha_mode")) continue;
        sp.alpha_mode = alphaModeOf(&entry.value) orelse {
            E.fail(out_error, .invalid_argument, "alpha_mode is one of 'opaque', 'mask' or 'blend'", @src());
            return false;
        };
    }
    return true;
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
    try testing.expect(ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
    try testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), cam.fov, 1e-6);
}

test "a field of view authored as a whole number of degrees is coerced, not ignored" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vInt(60))};
    try testing.expect(ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
    try testing.expectApproxEqAbs(@as(f32, std.math.pi / 3.0), cam.fov, 1e-6);
}

test "claiming the field of view key marks it consumed so the loader stops calling it unknown" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vFloat(45.0))};
    try testing.expect(ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
    try testing.expect(list[0].consumed);
}

test "a key the camera does not know is left unconsumed for someone else" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov", vFloat(45.0))};
    try testing.expect(ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
    try testing.expect(!list[0].consumed);
    try testing.expectEqual(@as(f32, 0), cam.fov);
}

test "a field of view authored as a string fails the load instead of being ignored" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    cam.fov = 1.25;
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vString("wide"))};
    try testing.expect(!ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(f32, 1.25), cam.fov);
}

test "a negative field of view fails the load rather than reaching the projection" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vFloat(-90.0))};
    try testing.expect(!ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(f32, 0), cam.fov);
}

test "a field of view of zero degrees fails the load" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vFloat(0))};
    try testing.expect(!ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
}

test "a field of view of half a turn or more fails the load, having no projection" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vFloat(180.0))};
    try testing.expect(!ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
}

test "the last field of view authored for a duplicated key wins" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{
        keyed("fov_degrees", vFloat(30.0)),
        keyed("fov_degrees", vFloat(90.0)),
    };
    try testing.expect(ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
    try testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), cam.fov, 1e-6);
}

test "an empty entry list leaves the camera alone" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    cam.fov = 2.0;
    try testing.expect(ke_render_apply_camera(null, &cam, null, 0, null));
    try testing.expectEqual(@as(f32, 2.0), cam.fov);
}

test "an entry with no key at all is skipped rather than dereferenced" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed(null, vFloat(90.0))};
    try testing.expect(ke_render_apply_camera(null, &cam, &list, @intCast(list.len), null));
    try testing.expect(!list[0].consumed);
    try testing.expectEqual(@as(f32, 0), cam.fov);
}

test "a mesh alpha mode authored as mask becomes the mask enumerator" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("mask"))};
    try testing.expect(ke_render_apply_mesh(null, &m, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_MASK), m.alpha_mode);
    try testing.expect(list[0].consumed);
}

test "a mesh alpha mode authored as blend becomes the blend enumerator" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("blend"))};
    try testing.expect(ke_render_apply_mesh(null, &m, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_BLEND), m.alpha_mode);
}

test "a mesh alpha mode authored as opaque becomes the opaque enumerator" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("opaque"))};
    try testing.expect(ke_render_apply_mesh(null, &m, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_OPAQUE), m.alpha_mode);
}

test "a misspelled mesh alpha mode fails the load rather than rendering opaque" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("blnd"))};
    try testing.expect(!ke_render_apply_mesh(null, &m, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_BLEND), m.alpha_mode);
}

test "a mesh alpha mode authored as a number fails the load" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vInt(1))};
    try testing.expect(!ke_render_apply_mesh(null, &m, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_BLEND), m.alpha_mode);
}

test "a mesh alpha mode authored as a null string fails the load" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString(null))};
    try testing.expect(!ke_render_apply_mesh(null, &m, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_BLEND), m.alpha_mode);
}

test "a key the mesh does not know is left unconsumed" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    var list = [_]c.ke_variant_table_entry{keyed("alphamode", vString("blend"))};
    try testing.expect(ke_render_apply_mesh(null, &m, &list, @intCast(list.len), null));
    try testing.expect(!list[0].consumed);
    try testing.expectEqual(@as(@TypeOf(m.alpha_mode), c.KE_ALPHA_MODE_OPAQUE), m.alpha_mode);
}

test "a sprite alpha mode authored as blend becomes the blend enumerator" {
    var sp = std.mem.zeroes(c.ke_sprite2d_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("blend"))};
    try testing.expect(ke_render_apply_sprite2d(null, &sp, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(@TypeOf(sp.alpha_mode), c.KE_ALPHA_MODE_BLEND), sp.alpha_mode);
    try testing.expect(list[0].consumed);
}

test "a sprite alpha mode authored as mask becomes the mask enumerator" {
    var sp = std.mem.zeroes(c.ke_sprite2d_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("mask"))};
    try testing.expect(ke_render_apply_sprite2d(null, &sp, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(@TypeOf(sp.alpha_mode), c.KE_ALPHA_MODE_MASK), sp.alpha_mode);
}

test "a misspelled sprite alpha mode fails the load, matching a mesh" {
    var sp = std.mem.zeroes(c.ke_sprite2d_component);
    sp.alpha_mode = c.KE_ALPHA_MODE_BLEND;
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("transparent"))};
    try testing.expect(!ke_render_apply_sprite2d(null, &sp, &list, @intCast(list.len), null));
    try testing.expectEqual(@as(@TypeOf(sp.alpha_mode), c.KE_ALPHA_MODE_BLEND), sp.alpha_mode);
}

test "a rejected field of view says it is measured in degrees instead of failing namelessly" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vString("wide"))};
    var err: [*c]c.ke_error = null;
    try testing.expect(!ke_render_apply_camera(null, &cam, &list, @intCast(list.len), &err));
    try testing.expect(err != null);
    try testing.expect(std.mem.indexOf(u8, std.mem.span(err.*.message), "degrees") != null);
}

test "a field of view outside the open half turn says which range it left" {
    var cam = std.mem.zeroes(c.ke_camera_component);
    var list = [_]c.ke_variant_table_entry{keyed("fov_degrees", vFloat(180.0))};
    var err: [*c]c.ke_error = null;
    try testing.expect(!ke_render_apply_camera(null, &cam, &list, @intCast(list.len), &err));
    try testing.expect(err != null);
    try testing.expect(std.mem.indexOf(u8, std.mem.span(err.*.message), "between 0 and 180") != null);
}

test "a misspelled alpha mode names the three spellings it could have been" {
    var m = std.mem.zeroes(c.ke_mesh_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("blnd"))};
    var err: [*c]c.ke_error = null;
    try testing.expect(!ke_render_apply_mesh(null, &m, &list, @intCast(list.len), &err));
    try testing.expect(err != null);
    try testing.expect(std.mem.indexOf(u8, std.mem.span(err.*.message), "'blend'") != null);
}

test "a sprite rejecting an alpha mode reports it the same way a mesh does" {
    var sp = std.mem.zeroes(c.ke_sprite2d_component);
    var list = [_]c.ke_variant_table_entry{keyed("alpha_mode", vString("transparent"))};
    var err: [*c]c.ke_error = null;
    try testing.expect(!ke_render_apply_sprite2d(null, &sp, &list, @intCast(list.len), &err));
    try testing.expect(err != null);
    try testing.expect(std.mem.indexOf(u8, std.mem.span(err.*.message), "'blend'") != null);
}

test "a sprite leaves every key it does not claim for the rest of the engine" {
    var sp = std.mem.zeroes(c.ke_sprite2d_component);
    var list = [_]c.ke_variant_table_entry{
        keyed("fov_degrees", vFloat(90)),
        keyed("alpha_mode", vString("mask")),
        keyed("texture", vString("res://sprite.png")),
    };
    try testing.expect(ke_render_apply_sprite2d(null, &sp, &list, @intCast(list.len), null));
    try testing.expect(!list[0].consumed);
    try testing.expect(list[1].consumed);
    try testing.expect(!list[2].consumed);
}

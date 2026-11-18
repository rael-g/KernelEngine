//! Reads a `ke_settings` into the struct an implementation declares as its settings: each field is
//! one key, its default value is the implementation's default, and a `ranges` declaration bounds
//! the numeric ones.

const std = @import("std");
const abi_settings = @import("abi_settings");
const abi_result = @import("abi_result");

const R = @import("result").Result(.{});
const log = std.log.scoped(.settings);

const c = abi_settings.c;

/// Fills a `T` from `settings`. A key that is absent keeps the field's default; a key of another
/// type than its field, a number outside the field's range, a string that names no value of an
/// enum field, and a key that names no field are refused as an invalid argument, each logged with
/// the key. `T` is a struct whose every field has a default and is a bool, an integer, a float, an
/// enum or a `[:0]const u8`; `T.ranges`, when declared, gives `.{ min, max }` per numeric field.
/// A string field borrows the settings' string, valid while the settings live.
pub fn read(comptime T: type, settings: *c.ke_settings) R.Error!T {
    var out: T = .{};
    inline for (@typeInfo(T).@"struct".fields) |field| {
        try readField(T, field, settings, &@field(out, field.name));
    }
    try refuseUnknown(T, settings);
    return out;
}

fn readField(comptime T: type, comptime field: std.builtin.Type.StructField, settings: *c.ke_settings, dst: *field.type) R.Error!void {
    const key: [:0]const u8 = field.name;
    switch (@typeInfo(field.type)) {
        .bool => {
            var v: bool = false;
            if (!try found(settings.get_bool.?(settings, key.ptr, &v), key, "a boolean")) return;
            dst.* = v;
        },
        .int => {
            var v: i64 = 0;
            if (!try found(settings.get_int.?(settings, key.ptr, &v), key, "an integer")) return;
            const lo, const hi = bounds(T, field.name, field.type);
            if (v < lo or v > hi) return outOfRange(key, v, lo, hi);
            dst.* = @intCast(v);
        },
        .float => {
            var v: f64 = 0;
            if (!try found(settings.get_double.?(settings, key.ptr, &v), key, "a number")) return;
            const lo, const hi = bounds(T, field.name, field.type);
            if (!(v >= lo and v <= hi)) return outOfRange(key, v, lo, hi);
            dst.* = @floatCast(v);
        },
        .@"enum" => {
            var v: ?[*:0]const u8 = null;
            if (!try found(settings.get_string.?(settings, key.ptr, &v), key, "a string")) return;
            dst.* = std.meta.stringToEnum(field.type, std.mem.span(v.?)) orelse {
                log.warn("setting {s}: '{s}' names no value of it", .{ key, v.? });
                return error.InvalidArgument;
            };
        },
        .pointer => {
            comptime std.debug.assert(field.type == [:0]const u8);
            var v: ?[*:0]const u8 = null;
            if (!try found(settings.get_string.?(settings, key.ptr, &v), key, "a string")) return;
            dst.* = std.mem.span(v.?);
        },
        else => @compileError("settings field " ++ field.name ++ " has a type no setting holds"),
    }
}

fn found(code: abi_result.c.ke_result, key: []const u8, kind: []const u8) R.Error!bool {
    if (code == R.ok) return true;
    R.check(code) catch |err| switch (err) {
        error.NotFound => return false,
        error.InvalidArgument => {
            log.warn("setting {s}: the value is not {s}", .{ key, kind });
            return err;
        },
        else => return err,
    };
    unreachable;
}

fn bounds(comptime T: type, comptime name: []const u8, comptime F: type) struct { if (@typeInfo(F) == .int) i64 else f64, if (@typeInfo(F) == .int) i64 else f64 } {
    const is_int = @typeInfo(F) == .int;
    if (@hasDecl(T, "ranges") and @hasField(@TypeOf(T.ranges), name)) {
        const r = @field(T.ranges, name);
        return .{ r[0], r[1] };
    }
    if (is_int) return .{ std.math.cast(i64, std.math.minInt(F)) orelse std.math.minInt(i64), std.math.cast(i64, std.math.maxInt(F)) orelse std.math.maxInt(i64) };
    return .{ -std.math.floatMax(f64), std.math.floatMax(f64) };
}

fn outOfRange(key: []const u8, v: anytype, lo: anytype, hi: anytype) R.Error {
    log.warn("setting {s}: {d} is outside {d} to {d}", .{ key, v, lo, hi });
    return error.InvalidArgument;
}

fn refuseUnknown(comptime T: type, settings: *c.ke_settings) R.Error!void {
    const Check = struct {
        unknown: bool = false,

        fn each(key_c: ?[*:0]const u8, ctx: ?*anyopaque) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const key = std.mem.span(key_c.?);
            inline for (@typeInfo(T).@"struct".fields) |field| {
                if (std.mem.eql(u8, key, field.name)) return;
            }
            log.warn("setting {s}: no such setting", .{key});
            self.unknown = true;
        }
    };
    var check: Check = .{};
    try R.check(settings.for_each_key.?(settings, Check.each, &check));
    if (check.unknown) return error.InvalidArgument;
}

/// One value a `Fixed` holds.
pub const Value = union(enum) { boolean: bool, int: i64, double: f64, string: [:0]const u8 };
/// One key of a `Fixed` and its value.
pub const Pair = struct { key: [:0]const u8, value: Value };

/// A `ke_settings` over a list of pairs the caller keeps alive, for settings made in code and for
/// tests; `api` is what a factory receives, and an integer is read as a number as well.
pub const Fixed = struct {
    api: c.ke_settings,
    pairs: []const Pair,

    pub fn init(pairs: []const Pair) Fixed {
        return .{ .api = .{ .handle = null, .get_bool = getBool, .get_int = getInt, .get_double = getDouble, .get_string = getString, .for_each_key = forEachKey }, .pairs = pairs };
    }

    fn lookup(self: ?*c.ke_settings, key: ?[*:0]const u8) ?Value {
        const f: *Fixed = @fieldParentPtr("api", self.?);
        for (f.pairs) |p| if (std.mem.eql(u8, p.key, std.mem.span(key.?))) return p.value;
        return null;
    }

    fn getBool(self: ?*c.ke_settings, key: ?[*:0]const u8, out: ?*bool) callconv(.c) abi_result.c.ke_result {
        const v = lookup(self, key) orelse return R.code(error.NotFound);
        if (v != .boolean) return R.code(error.InvalidArgument);
        out.?.* = v.boolean;
        return R.ok;
    }

    fn getInt(self: ?*c.ke_settings, key: ?[*:0]const u8, out: ?*i64) callconv(.c) abi_result.c.ke_result {
        const v = lookup(self, key) orelse return R.code(error.NotFound);
        if (v != .int) return R.code(error.InvalidArgument);
        out.?.* = v.int;
        return R.ok;
    }

    fn getDouble(self: ?*c.ke_settings, key: ?[*:0]const u8, out: ?*f64) callconv(.c) abi_result.c.ke_result {
        const v = lookup(self, key) orelse return R.code(error.NotFound);
        out.?.* = switch (v) {
            .double => |d| d,
            .int => |i| @floatFromInt(i),
            else => return R.code(error.InvalidArgument),
        };
        return R.ok;
    }

    fn getString(self: ?*c.ke_settings, key: ?[*:0]const u8, out: ?*?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
        const v = lookup(self, key) orelse return R.code(error.NotFound);
        if (v != .string) return R.code(error.InvalidArgument);
        out.?.* = v.string.ptr;
        return R.ok;
    }

    fn forEachKey(self: ?*c.ke_settings, each: c.ke_settings_key_func, ctx: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
        const f: *Fixed = @fieldParentPtr("api", self.?);
        for (f.pairs) |p| each.?(p.key.ptr, ctx);
        return R.ok;
    }
};

const testing = std.testing;

const Mode = enum { fifo, mailbox };

const Example = struct {
    title: [:0]const u8 = "untitled",
    width: u32 = 640,
    scale: f32 = 1.0,
    vsync: bool = true,
    mode: Mode = .fifo,

    pub const ranges = .{ .width = .{ 1, 4096 }, .scale = .{ 0.5, 4.0 } };
};

test "settings that write nothing read as the implementation's defaults" {
    var s = Fixed.init(&.{});
    const v = try read(Example, &s.api);
    try testing.expectEqualStrings("untitled", v.title);
    try testing.expectEqual(@as(u32, 640), v.width);
    try testing.expect(v.vsync and v.mode == .fifo and v.scale == 1.0);
}

test "each written key replaces its default, an integer reads as a number and a string names an enum value" {
    var s = Fixed.init(&.{
        .{ .key = "title", .value = .{ .string = "Pong" } },
        .{ .key = "width", .value = .{ .int = 960 } },
        .{ .key = "scale", .value = .{ .int = 2 } },
        .{ .key = "vsync", .value = .{ .boolean = false } },
        .{ .key = "mode", .value = .{ .string = "mailbox" } },
    });
    const v = try read(Example, &s.api);
    try testing.expectEqualStrings("Pong", v.title);
    try testing.expectEqual(@as(u32, 960), v.width);
    try testing.expectEqual(@as(f32, 2.0), v.scale);
    try testing.expect(!v.vsync and v.mode == .mailbox);
}

test "a value of the wrong type, outside its range, naming no enum value, or under no setting is refused" {
    const cases = [_][]const Pair{
        &.{.{ .key = "width", .value = .{ .string = "wide" } }},
        &.{.{ .key = "width", .value = .{ .int = 0 } }},
        &.{.{ .key = "scale", .value = .{ .double = 8.0 } }},
        &.{.{ .key = "mode", .value = .{ .string = "immediate" } }},
        &.{.{ .key = "heigth", .value = .{ .int = 480 } }},
    };
    for (cases) |pairs| {
        var s = Fixed.init(pairs);
        try testing.expectError(error.InvalidArgument, read(Example, &s.api));
    }
}

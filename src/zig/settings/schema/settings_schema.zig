//! Reads a `ke_settings` into the struct an implementation declares as its settings: each field is
//! one key (an array field one key per element, `name.0`, `name.1`…), its default value is the
//! implementation's default, and a `ranges` declaration bounds the numeric ones.

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
/// enum, a `[:0]const u8`, an array of bool, integer or float, each element under `name.<index>`, or
/// an optional of one of those, null while its key is absent;
/// `T.ranges`, when declared, gives `.{ min, max }` per numeric field, for every element of an array.
/// A child the settings hold is refused unless `T.children`, when declared, names it; the part reads
/// the children it names itself. A string field borrows the settings' string, valid while the
/// settings live.
pub fn read(comptime T: type, settings: *c.ke_settings) R.Error!T {
    var out: T = .{};
    inline for (@typeInfo(T).@"struct".fields) |field| {
        switch (@typeInfo(field.type)) {
            .array => |a| inline for (0..a.len) |i| {
                try readValue(T, field.name, a.child, field.name ++ std.fmt.comptimePrint(".{d}", .{i}), settings, &@field(out, field.name)[i]);
            },
            .optional => |o| {
                var v: o.child = undefined;
                if (try readPresent(T, field.name, o.child, field.name, settings, &v)) @field(out, field.name) = v;
            },
            else => try readValue(T, field.name, field.type, field.name, settings, &@field(out, field.name)),
        }
    }
    try refuseUnknown(T, settings);
    return out;
}

fn readPresent(comptime T: type, comptime name: []const u8, comptime F: type, comptime key: [:0]const u8, settings: *c.ke_settings, dst: *F) R.Error!bool {
    var marker: struct { seen: bool = false } = .{};
    const Seen = struct {
        fn each(key_c: ?[*:0]const u8, ctx: ?*anyopaque) callconv(.c) void {
            const m: *@TypeOf(marker) = @ptrCast(@alignCast(ctx));
            if (std.mem.eql(u8, std.mem.span(key_c.?), key)) m.seen = true;
        }
    };
    try R.check(settings.for_each_key.?(settings, Seen.each, &marker));
    if (!marker.seen) return false;
    try readValue(T, name, F, key, settings, dst);
    return true;
}

fn readValue(comptime T: type, comptime name: []const u8, comptime F: type, comptime key: [:0]const u8, settings: *c.ke_settings, dst: *F) R.Error!void {
    switch (@typeInfo(F)) {
        .bool => {
            var v: bool = false;
            if (!try found(settings.get_bool.?(settings, key.ptr, &v), key, "a boolean")) return;
            dst.* = v;
        },
        .int => {
            var v: i64 = 0;
            if (!try found(settings.get_int.?(settings, key.ptr, &v), key, "an integer")) return;
            const lo, const hi = bounds(T, name, F);
            if (v < lo or v > hi) return outOfRange(key, v, lo, hi);
            dst.* = @intCast(v);
        },
        .float => {
            var v: f64 = 0;
            if (!try found(settings.get_double.?(settings, key.ptr, &v), key, "a number")) return;
            const lo, const hi = bounds(T, name, F);
            if (!(v >= lo and v <= hi)) return outOfRange(key, v, lo, hi);
            dst.* = @floatCast(v);
        },
        .@"enum" => {
            var v: ?[*:0]const u8 = null;
            if (!try found(settings.get_string.?(settings, key.ptr, &v), key, "a string")) return;
            dst.* = std.meta.stringToEnum(F, std.mem.span(v.?)) orelse {
                log.warn("setting {s}: '{s}' names no value of it", .{ key, v.? });
                return error.InvalidArgument;
            };
        },
        .pointer => {
            comptime std.debug.assert(F == [:0]const u8);
            var v: ?[*:0]const u8 = null;
            if (!try found(settings.get_string.?(settings, key.ptr, &v), key, "a string")) return;
            dst.* = std.mem.span(v.?);
        },
        else => @compileError("settings field " ++ name ++ " has a type no setting holds"),
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
                switch (@typeInfo(field.type)) {
                    .array => |a| inline for (0..a.len) |i| {
                        if (std.mem.eql(u8, key, field.name ++ std.fmt.comptimePrint(".{d}", .{i}))) return;
                    },
                    else => if (std.mem.eql(u8, key, field.name)) return,
                }
            }
            log.warn("setting {s}: no such setting", .{key});
            self.unknown = true;
        }
    };
    var check: Check = .{};
    try R.check(settings.for_each_key.?(settings, Check.each, &check));
    const ChildCheck = struct {
        fn each(name_c: ?[*:0]const u8, ctx: ?*anyopaque) callconv(.c) void {
            const self: *Check = @ptrCast(@alignCast(ctx));
            const name = std.mem.span(name_c.?);
            if (@hasDecl(T, "children")) inline for (T.children) |declared| if (std.mem.eql(u8, name, declared)) return;
            log.warn("setting {s}: no such setting", .{name});
            self.unknown = true;
        }
    };
    try R.check(settings.for_each_child.?(settings, ChildCheck.each, &check));
    if (check.unknown) return error.InvalidArgument;
}

/// One value a `Fixed` holds.
pub const Value = union(enum) { boolean: bool, int: i64, double: f64, string: [:0]const u8 };
/// One key of a `Fixed` and its value.
pub const Pair = struct { key: [:0]const u8, value: Value };

/// One child of a `Fixed`, under its name.
pub const Child = struct { name: [:0]const u8, settings: *Fixed };

/// A `ke_settings` over a list of pairs and of children the caller keeps alive, for settings made in
/// code and for tests; `api` is what a factory receives, and an integer is read as a number as well.
/// A child it does not hold is `empty`.
pub const Fixed = struct {
    api: c.ke_settings,
    pairs: []const Pair,
    children: []const Child = &.{},

    pub fn init(pairs: []const Pair) Fixed {
        return tree(pairs, &.{});
    }

    pub fn tree(pairs: []const Pair, children: []const Child) Fixed {
        return .{ .api = .{ .handle = null, .get_bool = getBool, .get_int = getInt, .get_double = getDouble, .get_string = getString, .for_each_key = forEachKey, .child = child, .for_each_child = forEachChild }, .pairs = pairs, .children = children };
    }

    var empty: Fixed = init(&.{});

    fn child(self: ?*c.ke_settings, name: ?[*:0]const u8, out: ?*?*c.ke_settings) callconv(.c) abi_result.c.ke_result {
        const f: *Fixed = @fieldParentPtr("api", self.?);
        for (f.children) |ch| if (std.mem.eql(u8, ch.name, std.mem.span(name.?))) {
            out.?.* = &ch.settings.api;
            return R.ok;
        };
        out.?.* = &empty.api;
        return R.ok;
    }

    fn forEachChild(self: ?*c.ke_settings, each: c.ke_settings_key_func, ctx: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
        const f: *Fixed = @fieldParentPtr("api", self.?);
        for (f.children) |ch| each.?(ch.name.ptr, ctx);
        return R.ok;
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
    tint: [3]f32 = .{ 0.0, 0.0, 1.0 },
    workers: ?u32 = null,

    pub const ranges = .{ .width = .{ 1, 4096 }, .scale = .{ 0.5, 4.0 }, .tint = .{ 0.0, 1.0 } };
};

test "settings that write nothing read as the implementation's defaults" {
    var s = Fixed.init(&.{});
    const v = try read(Example, &s.api);
    try testing.expectEqualStrings("untitled", v.title);
    try testing.expectEqual(@as(u32, 640), v.width);
    try testing.expect(v.vsync and v.mode == .fifo and v.scale == 1.0);
    try testing.expectEqual(@as(?u32, null), v.workers);
}

test "each written key replaces its default, an integer reads as a number and a string names an enum value" {
    var s = Fixed.init(&.{
        .{ .key = "title", .value = .{ .string = "Pong" } },
        .{ .key = "width", .value = .{ .int = 960 } },
        .{ .key = "scale", .value = .{ .int = 2 } },
        .{ .key = "vsync", .value = .{ .boolean = false } },
        .{ .key = "mode", .value = .{ .string = "mailbox" } },
        .{ .key = "tint.1", .value = .{ .double = 0.5 } },
        .{ .key = "workers", .value = .{ .int = 3 } },
    });
    const v = try read(Example, &s.api);
    try testing.expectEqualStrings("Pong", v.title);
    try testing.expectEqual(@as(u32, 960), v.width);
    try testing.expectEqual(@as(f32, 2.0), v.scale);
    try testing.expect(!v.vsync and v.mode == .mailbox);
    try testing.expectEqual([3]f32{ 0.0, 0.5, 1.0 }, v.tint);
    try testing.expectEqual(@as(?u32, 3), v.workers);
}

test "a value of the wrong type, outside its range, naming no enum value, or under no setting is refused" {
    const cases = [_][]const Pair{
        &.{.{ .key = "width", .value = .{ .string = "wide" } }},
        &.{.{ .key = "width", .value = .{ .int = 0 } }},
        &.{.{ .key = "scale", .value = .{ .double = 8.0 } }},
        &.{.{ .key = "mode", .value = .{ .string = "immediate" } }},
        &.{.{ .key = "heigth", .value = .{ .int = 480 } }},
        &.{.{ .key = "tint.3", .value = .{ .double = 0.5 } }},
        &.{.{ .key = "tint.0", .value = .{ .double = 2.0 } }},
    };
    for (cases) |pairs| {
        var s = Fixed.init(pairs);
        try testing.expectError(error.InvalidArgument, read(Example, &s.api));
    }
}

test "a child the type does not declare is refused, and one it declares is left to the part" {
    var inner = Fixed.init(&.{.{ .key = "frame", .value = .{ .int = 1 } }});
    var s = Fixed.tree(&.{}, &.{.{ .name = "script", .settings = &inner }});
    try testing.expectError(error.InvalidArgument, read(Example, &s.api));
    const Scripted = struct {
        frames: u32 = 1,
        pub const children = .{"script"};
    };
    _ = try read(Scripted, &s.api);
    var got: ?*c.ke_settings = null;
    try R.check(s.api.child.?(&s.api, "script", &got));
    var frame: i64 = 0;
    try R.check(got.?.get_int.?(got.?, "frame", &frame));
    try testing.expectEqual(@as(i64, 1), frame);
}

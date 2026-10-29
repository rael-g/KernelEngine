//! A configuration source that loads a TOML file into a configuration through the setter slots of
//! its contract.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_configuration_toml").logFn };

const toml = @import("c");
const abi_configuration = @import("abi_configuration");
const abi_io = @import("abi_io");
const abi_toml = @import("abi_configuration_toml_factory");
const abi_result = @import("abi_result");

const heap = @import("heap");
const gpa = heap.gpa;

const R = @import("result").Result(.{});
const log = std.log.scoped(.configuration_toml);

/// A value that matches none of the four readings is skipped without an error.
fn setScalar(cfg: [*c]abi_configuration.ke_configuration, section: [:0]const u8, key: [*c]const u8, tab: ?*toml.toml_table_t) R.Error!void {
    const di = toml.toml_int_in(tab, key);
    if (di.ok != 0) return R.check(cfg.*.set_int.?(cfg, section.ptr, key, di.u.i));

    const dd = toml.toml_double_in(tab, key);
    if (dd.ok != 0) return R.check(cfg.*.set_double.?(cfg, section.ptr, key, dd.u.d));

    const db = toml.toml_bool_in(tab, key);
    if (db.ok != 0) return R.check(cfg.*.set_bool.?(cfg, section.ptr, key, db.u.b != 0));

    const ds = toml.toml_string_in(tab, key);
    if (ds.ok != 0) {
        defer std.c.free(ds.u.s);
        return R.check(cfg.*.set_string.?(cfg, section.ptr, key, ds.u.s));
    }
}

/// Recursive; `load` makes the first call. A failed write or a failed section allocation returns
/// its error at once, and writes already made are not undone. The section path of a sub-table is
/// freed when its recursive call returns.
fn walkTable(cfg: [*c]abi_configuration.ke_configuration, tab: ?*toml.toml_table_t, section: [:0]const u8) R.Error!void {
    const n = toml.toml_table_nkval(tab) + toml.toml_table_narr(tab) + toml.toml_table_ntab(tab);
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        const key = toml.toml_key_in(tab, i);
        if (key == null) continue;

        if (toml.toml_table_in(tab, key)) |sub| {
            const child = if (section.len == 0)
                try gpa.dupeZ(u8, std.mem.span(key))
            else
                try std.fmt.allocPrintSentinel(gpa, "{s}.{s}", .{ section, std.mem.span(key) }, 0);
            defer gpa.free(child);
            try walkTable(cfg, sub, child);
        } else if (toml.toml_array_in(tab, key) != null) {
            continue;
        } else {
            try setScalar(cfg, section, key, tab);
        }
    }
}

/// The state behind the source the factory returns: the vtable and the borrowed io every load
/// reads through; a load keeps nothing between calls.
const State = struct {
    api: abi_configuration.ke_configuration_source,
    io: *abi_io.ke_io,
};

fn isFile(io: *abi_io.ke_io, path: [*c]const u8) R.Error!bool {
    var request: ?*abi_io.ke_io_request = null;
    try R.check(io.file_exists.?(io, path, &request));
    var result: abi_io.ke_io_result = undefined;
    try R.check(io.wait.?(io, request, &result));
    return result.exists;
}

/// The whole file at `path` with a terminating zero, owned by the caller; null when there is no
/// such file, which is asked first so that its absence is not a failed read.
fn readText(io: *abi_io.ke_io, path: [*c]const u8) R.Error!?[:0]u8 {
    if (!try isFile(io, path)) return null;
    var request: ?*abi_io.ke_io_request = null;
    try R.check(io.read_file.?(io, path, &request));
    var result: abi_io.ke_io_result = undefined;
    R.check(io.wait.?(io, request, &result)) catch |err| {
        log.warn("reading {s} failed: {t}", .{ path, err });
        return err;
    };
    defer io.free_bytes.?(io, result.bytes);
    const bytes: []const u8 = if (result.bytes) |b| @as([*]const u8, @ptrCast(b))[0..@intCast(result.size)] else "";
    return try gpa.dupeZ(u8, bytes);
}

/// Slot `load`. A file that does not exist succeeds with nothing written. A parse error fails
/// with general before any write, so the configuration is left unchanged, and the parser's message
/// is logged. The first failed write stops the walk and the writes before it stay. A null source,
/// configuration or path is an invalid argument.
fn load(self: [*c]abi_configuration.ke_configuration_source, cfg: [*c]abi_configuration.ke_configuration, path: [*c]const u8) callconv(.c) abi_result.ke_result {
    if (self == null or cfg == null or path == null) return R.code(error.InvalidArgument);
    const text = (readText(stateOf(self).io, path) catch |err| return R.code(err)) orelse return R.ok;
    defer gpa.free(text);

    var errbuf: [256]u8 = std.mem.zeroes([256]u8);
    const root = toml.toml_parse(text.ptr, &errbuf, errbuf.len);
    if (root == null) {
        log.warn("{s} does not parse: {s}", .{ path, std.mem.sliceTo(&errbuf, 0) });
        return R.code(error.General);
    }
    defer toml.toml_free(root);

    walkTable(cfg, root, "") catch |err| {
        log.warn("loading {s} failed: {t}", .{ path, err });
        return R.code(err);
    };
    return R.ok;
}

fn stateOf(self: [*c]abi_configuration.ke_configuration_source) *State {
    return @fieldParentPtr("api", @as(*abi_configuration.ke_configuration_source, @ptrCast(self)));
}

fn destroy(self: [*c]abi_configuration.ke_configuration_source) callconv(.c) void {
    if (self == null) return;
    gpa.destroy(stateOf(self));
}

/// The factory. Fails with out of memory, leaving the handle zeroed, when the state cannot be
/// allocated.
export fn ke_configuration_toml_create(params: ?*const abi_toml.ke_configuration_toml_params, out_source: ?*abi_configuration.ke_configuration_source_handle) callconv(.c) abi_result.ke_result {
    const out = out_source orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_configuration.ke_configuration_source_handle);
    const p = params orelse return R.code(error.InvalidArgument);
    const io = p.io orelse return R.code(error.InvalidArgument);
    const s = gpa.create(State) catch {
        log.warn("creating the TOML source failed: out of memory", .{});
        return R.code(error.OutOfMemory);
    };
    s.* = .{ .api = std.mem.zeroes(abi_configuration.ke_configuration_source), .io = io };
    s.api.handle = s;
    s.api.load = load;
    out.* = .{ .ref = &s.api, .destroy = destroy };
    return R.ok;
}

const RecVal = union(enum) { int: i64, double: f64, boolean: bool, string: [:0]u8 };

/// A write captured by a mock setter. `section`, `key` and a string `value` are owned copies,
/// freed by `clearRecs`.
const Rec = struct {
    section: [:0]u8,
    key: [:0]u8,
    value: RecVal,
};

/// Writes captured by the mock setters until `clearRecs` empties it.
var g_recs: std.ArrayListUnmanaged(Rec) = .empty;

fn recPush(section: [*c]const u8, key: [*c]const u8, value: RecVal) void {
    g_recs.append(gpa, .{
        .section = gpa.dupeZ(u8, std.mem.span(section)) catch unreachable,
        .key = gpa.dupeZ(u8, std.mem.span(key)) catch unreachable,
        .value = value,
    }) catch unreachable;
}

fn mockSetInt(_: [*c]abi_configuration.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: i64) callconv(.c) abi_result.ke_result {
    recPush(s, k, RecVal{ .int = v });
    return R.ok;
}
fn mockSetDouble(_: [*c]abi_configuration.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: f64) callconv(.c) abi_result.ke_result {
    recPush(s, k, RecVal{ .double = v });
    return R.ok;
}
fn mockSetBool(_: [*c]abi_configuration.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: bool) callconv(.c) abi_result.ke_result {
    recPush(s, k, RecVal{ .boolean = v });
    return R.ok;
}
fn mockSetString(_: [*c]abi_configuration.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: [*c]const u8) callconv(.c) abi_result.ke_result {
    recPush(s, k, RecVal{ .string = gpa.dupeZ(u8, std.mem.span(v)) catch unreachable });
    return R.ok;
}

const zsub = @import("zsub");

var served: ?[]const u8 = null;
var request_token: u8 = 0;

fn readServed(args: zsub.For(abi_io.ke_io).Args(.read_file)) abi_result.ke_result {
    args[2].?.* = @ptrCast(&request_token);
    return R.ok;
}

var exists_token: u8 = 0;

fn existsServed(args: zsub.For(abi_io.ke_io).Args(.file_exists)) abi_result.ke_result {
    args[2].?.* = @ptrCast(&exists_token);
    return R.ok;
}

fn waitServed(args: zsub.For(abi_io.ke_io).Args(.wait)) abi_result.ke_result {
    if (args[2]) |out| out.* = std.mem.zeroes(abi_io.ke_io_result);
    if (args[1] == @as(?*abi_io.ke_io_request, @ptrCast(&exists_token))) {
        if (args[2]) |out| out.exists = served != null;
        return R.ok;
    }
    const text = served orelse return R.code(error.NotFound);
    if (args[2]) |out| {
        out.bytes = @constCast(text.ptr);
        out.size = text.len;
    }
    return R.ok;
}

fn freeServed(_: zsub.For(abi_io.ke_io).Args(.free_bytes)) void {}

/// A substitute io serving `text` for every path, or no file at all when `text` is null.
fn servingIo(sub: *zsub.For(abi_io.ke_io), text: ?[]const u8) !*abi_io.ke_io {
    served = text;
    try sub.init();
    _ = sub.when(.read_file).does(readServed);
    _ = sub.when(.file_exists).does(existsServed);
    _ = sub.when(.wait).does(waitServed);
    _ = sub.when(.free_bytes).does(freeServed);
    return sub.api();
}

fn madeSource(io: *abi_io.ke_io) !abi_configuration.ke_configuration_source_handle {
    var h: abi_configuration.ke_configuration_source_handle = undefined;
    try R.check(ke_configuration_toml_create(&.{ .io = io }, &h));
    return h;
}

fn testLoad(cfg: *abi_configuration.ke_configuration, text: ?[]const u8) !bool {
    var sub: zsub.For(abi_io.ke_io) = undefined;
    const io = try servingIo(&sub, text);
    defer sub.deinit();
    const h = try madeSource(io);
    defer h.destroy.?(h.ref);
    const loaded = h.ref.?.load.?(h.ref, cfg, "Project") == R.ok;
    if (text == null) try sub.received(.read_file).never();
    return loaded;
}

fn mockConfig() abi_configuration.ke_configuration {
    var c: abi_configuration.ke_configuration = std.mem.zeroes(abi_configuration.ke_configuration);
    c.set_int = mockSetInt;
    c.set_double = mockSetDouble;
    c.set_bool = mockSetBool;
    c.set_string = mockSetString;
    return c;
}

fn clearRecs() void {
    for (g_recs.items) |*r| {
        gpa.free(r.section);
        gpa.free(r.key);
        switch (r.value) {
            .string => |sv| gpa.free(sv),
            else => {},
        }
    }
    g_recs.clearAndFree(gpa);
}

fn findInt(section: []const u8, key: []const u8) ?i64 {
    for (g_recs.items) |r| {
        if (std.mem.eql(u8, r.section, section) and std.mem.eql(u8, r.key, key)) {
            switch (r.value) {
                .int => |v| return v,
                else => {},
            }
        }
    }
    return null;
}

test "loads typed scalars per section" {
    defer clearRecs();
    const text =
        \\[shadow]
        \\resolution = 2048
        \\frustum_size = 30.5
        \\soft = false
        \\[render]
        \\shader_path = "res/shaders"
        \\
    ;

    var cfg = mockConfig();
    try std.testing.expect(try testLoad(&cfg, text));

    try std.testing.expectEqual(@as(?i64, 2048), findInt("shadow", "resolution"));

    var seen_double = false;
    var seen_bool = false;
    var seen_string = false;
    for (g_recs.items) |r| {
        if (std.mem.eql(u8, r.section, "shadow") and std.mem.eql(u8, r.key, "frustum_size")) {
            try std.testing.expectEqual(@as(f64, 30.5), r.value.double);
            seen_double = true;
        }
        if (std.mem.eql(u8, r.section, "shadow") and std.mem.eql(u8, r.key, "soft")) {
            try std.testing.expectEqual(false, r.value.boolean);
            seen_bool = true;
        }
        if (std.mem.eql(u8, r.section, "render") and std.mem.eql(u8, r.key, "shader_path")) {
            try std.testing.expectEqualStrings("res/shaders", r.value.string);
            seen_string = true;
        }
    }
    try std.testing.expect(seen_double and seen_bool and seen_string);
}

test "dotted sub-tables flatten to dotted section names" {
    defer clearRecs();
    const text =
        \\[shadow.cascade]
        \\count = 4
        \\
    ;

    var cfg = mockConfig();
    try std.testing.expect(try testLoad(&cfg, text));
    try std.testing.expectEqual(@as(?i64, 4), findInt("shadow.cascade", "count"));
}

test "a missing file is not an error, is never read and writes nothing" {
    defer clearRecs();
    var cfg = mockConfig();
    try std.testing.expect(try testLoad(&cfg, null));
    try std.testing.expectEqual(@as(usize, 0), g_recs.items.len);
}

test "parse error returns false" {
    defer clearRecs();
    const text = "this is = = not valid toml\n";

    var cfg = mockConfig();
    try std.testing.expect(!try testLoad(&cfg, text));
}

test "null args rejected" {
    defer clearRecs();
    var cfg = mockConfig();
    var sub: zsub.For(abi_io.ke_io) = undefined;
    const io = try servingIo(&sub, null);
    defer sub.deinit();
    var none: abi_configuration.ke_configuration_source_handle = undefined;
    try std.testing.expectError(error.InvalidArgument, R.check(ke_configuration_toml_create(null, &none)));
    try std.testing.expectError(error.InvalidArgument, R.check(ke_configuration_toml_create(&.{}, &none)));
    const h = try madeSource(io);
    defer h.destroy.?(h.ref);
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.?.load.?(null, &cfg, "x")));
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.?.load.?(h.ref, null, "x")));
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.?.load.?(h.ref, &cfg, null)));
}

test "loading a file and clearing the recorded values leaves no block allocated" {
    const text =
        \\[shadow]
        \\resolution = 2048
        \\[render]
        \\shader_path = "res/shaders"
        \\
    ;

    var cfg = mockConfig();
    try std.testing.expect(try testLoad(&cfg, text));
    clearRecs();
    try heap.expectNoLeaks();
}

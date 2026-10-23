//! A configuration source that loads a TOML file into a configuration through the setter slots of
//! its contract.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_configuration_toml").logFn };

const toml = @import("c");
const ke = @import("c");

const heap = @import("heap");
const gpa = heap.gpa;

const R = @import("result").Result(ke, .{});
const log = std.log.scoped(.configuration_toml);

/// A value that matches none of the four readings is skipped without an error.
fn setScalar(cfg: [*c]ke.ke_configuration, section: [:0]const u8, key: [*c]const u8, tab: ?*toml.toml_table_t) R.Error!void {
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
fn walkTable(cfg: [*c]ke.ke_configuration, tab: ?*toml.toml_table_t, section: [:0]const u8) R.Error!void {
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

/// The state behind the source the factory returns; it holds nothing but the vtable, since a load
/// keeps nothing between calls.
const State = struct {
    api: ke.ke_configuration_source,
};

/// Slot `load`. A file that cannot be opened succeeds with nothing written. A parse error fails
/// with general before any write, so the configuration is left unchanged, and the parser's message
/// is logged. The first failed write stops the walk and the writes before it stay. A null source,
/// configuration or path is an invalid argument.
fn load(self: [*c]ke.ke_configuration_source, cfg: [*c]ke.ke_configuration, path: [*c]const u8) callconv(.c) ke.ke_result {
    if (self == null or cfg == null or path == null) return R.code(error.InvalidArgument);
    const fp = toml.fopen(path, "r");
    if (fp == null) return R.ok;
    defer _ = toml.fclose(fp);

    var errbuf: [256]u8 = std.mem.zeroes([256]u8);
    const root = toml.toml_parse_file(fp, &errbuf, errbuf.len);
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

fn stateOf(self: [*c]ke.ke_configuration_source) *State {
    return @fieldParentPtr("api", @as(*ke.ke_configuration_source, @ptrCast(self)));
}

fn destroy(self: [*c]ke.ke_configuration_source) callconv(.c) void {
    if (self == null) return;
    gpa.destroy(stateOf(self));
}

/// The factory. Fails with out of memory, leaving the handle zeroed, when the state cannot be
/// allocated.
export fn ke_configuration_toml_create(out_source: ?*ke.ke_configuration_source_handle) callconv(.c) ke.ke_result {
    const out = out_source orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(ke.ke_configuration_source_handle);
    const s = gpa.create(State) catch {
        log.warn("creating the TOML source failed: out of memory", .{});
        return R.code(error.OutOfMemory);
    };
    s.* = .{ .api = std.mem.zeroes(ke.ke_configuration_source) };
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

fn mockSetInt(_: [*c]ke.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: i64) callconv(.c) ke.ke_result {
    recPush(s, k, RecVal{ .int = v });
    return R.ok;
}
fn mockSetDouble(_: [*c]ke.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: f64) callconv(.c) ke.ke_result {
    recPush(s, k, RecVal{ .double = v });
    return R.ok;
}
fn mockSetBool(_: [*c]ke.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: bool) callconv(.c) ke.ke_result {
    recPush(s, k, RecVal{ .boolean = v });
    return R.ok;
}
fn mockSetString(_: [*c]ke.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: [*c]const u8) callconv(.c) ke.ke_result {
    recPush(s, k, RecVal{ .string = gpa.dupeZ(u8, std.mem.span(v)) catch unreachable });
    return R.ok;
}

fn madeSource() !ke.ke_configuration_source_handle {
    var h: ke.ke_configuration_source_handle = undefined;
    try R.check(ke_configuration_toml_create(&h));
    return h;
}

fn testLoad(cfg: *ke.ke_configuration, path: [*c]const u8) !bool {
    const h = try madeSource();
    defer h.destroy.?(h.ref);
    return h.ref.*.load.?(h.ref, cfg, path) == R.ok;
}

fn mockConfig() ke.ke_configuration {
    var c: ke.ke_configuration = std.mem.zeroes(ke.ke_configuration);
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

fn writeTemp(name: [*c]const u8, data: []const u8) void {
    const fp = toml.fopen(name, "w");
    if (fp == null) return;
    _ = toml.fwrite(data.ptr, 1, data.len, fp);
    _ = toml.fclose(fp);
}

test "loads typed scalars per section" {
    defer clearRecs();
    const path = "test_cfg_scalars.toml";
    writeTemp(path,
        \\[shadow]
        \\resolution = 2048
        \\frustum_size = 30.5
        \\soft = false
        \\[render]
        \\shader_path = "res/shaders"
        \\
    );
    defer _ = toml.remove(path);

    var cfg = mockConfig();
    try std.testing.expect(try testLoad(&cfg, path));

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
    const path = "test_cfg_dotted.toml";
    writeTemp(path,
        \\[shadow.cascade]
        \\count = 4
        \\
    );
    defer _ = toml.remove(path);

    var cfg = mockConfig();
    try std.testing.expect(try testLoad(&cfg, path));
    try std.testing.expectEqual(@as(?i64, 4), findInt("shadow.cascade", "count"));
}

test "missing file is not an error and writes nothing" {
    defer clearRecs();
    var cfg = mockConfig();
    try std.testing.expect(try testLoad(&cfg, "does/not/exist/Project.toml"));
    try std.testing.expectEqual(@as(usize, 0), g_recs.items.len);
}

test "parse error returns false" {
    defer clearRecs();
    const path = "test_cfg_bad.toml";
    writeTemp(path, "this is = = not valid toml\n");
    defer _ = toml.remove(path);

    var cfg = mockConfig();
    try std.testing.expect(!try testLoad(&cfg, path));
}

test "null args rejected" {
    defer clearRecs();
    var cfg = mockConfig();
    const h = try madeSource();
    defer h.destroy.?(h.ref);
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.*.load.?(null, &cfg, "x")));
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.*.load.?(h.ref, null, "x")));
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.*.load.?(h.ref, &cfg, null)));
}

test "loading a file and clearing the recorded values leaves no block allocated" {
    const path = "test_cfg_leaks.toml";
    writeTemp(path,
        \\[shadow]
        \\resolution = 2048
        \\[render]
        \\shader_path = "res/shaders"
        \\
    );
    defer _ = toml.remove(path);

    var cfg = mockConfig();
    try std.testing.expect(try testLoad(&cfg, path));
    clearRecs();
    try heap.expectNoLeaks();
}

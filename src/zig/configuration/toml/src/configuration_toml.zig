// ke_configuration_toml — TOML loader for the ke_configuration store (Zig).
//
// Parses Project.toml via the vendored tomlc99 (third_party/tomlc99, consumed by
// @cImport) and populates a caller-owned ke_configuration through its set_*
// slots. The store stays format-agnostic; this module is the only place TOML is
// known. No Zig-package TOML parser was 0.16-ready, so the proven C parser is
// vendored and compiled by this module's build.zig (see the VENDOR.md).

const std = @import("std");

// This .so is dlopen'd by a foreign, non-Zig host alongside many sibling
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack exceeds glibc's small static-TLS surplus once enough plugins
// accumulate, aborting with "cannot allocate memory in static TLS block".
pub const std_options: std.Options = .{ .signal_stack_size = null };
const toml = @cImport({
    @cInclude("stdio.h");
    @cInclude("toml.h");
});
const ke = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/configuration/configuration.h");
});

const gpa = @import("heap.zig").gpa;

fn setErr(out_error: ?*?*ke.ke_error, etype: *const ke.ke_error_type, msg: [*c]const u8, src: std.builtin.SourceLocation) void {
    ke.ke_error_set(out_error, etype, msg, src.file, @intCast(src.line), null);
}

// Reads the scalar at `key` from `tab` and writes it into cfg[section][key].
// tomlc99 is type-strict, so exactly one of the typed accessors reports ok.
// Arrays and timestamps are skipped (returns true without writing).
fn setScalar(cfg: [*c]ke.ke_configuration, section: [:0]const u8, key: [*c]const u8, tab: ?*toml.toml_table_t, out_error: ?*?*ke.ke_error) bool {
    const di = toml.toml_int_in(tab, key);
    if (di.ok != 0) return cfg.*.set_int.?(cfg, section.ptr, key, di.u.i, out_error);

    const dd = toml.toml_double_in(tab, key);
    if (dd.ok != 0) return cfg.*.set_double.?(cfg, section.ptr, key, dd.u.d, out_error);

    const db = toml.toml_bool_in(tab, key);
    if (db.ok != 0) return cfg.*.set_bool.?(cfg, section.ptr, key, db.u.b != 0, out_error);

    const ds = toml.toml_string_in(tab, key);
    if (ds.ok != 0) {
        defer std.c.free(ds.u.s);
        return cfg.*.set_string.?(cfg, section.ptr, key, ds.u.s, out_error);
    }
    return true; // array / timestamp / unknown — skip
}

// Recursively walks a table. `section` is the dotted path built so far ("" at
// the root). tomlc99's toml_key_in enumerates kval, then arr, then sub-table
// keys; toml_table_in disambiguates a sub-table from a scalar.
fn walkTable(cfg: [*c]ke.ke_configuration, tab: ?*toml.toml_table_t, section: [:0]const u8, out_error: ?*?*ke.ke_error) bool {
    const n = toml.toml_table_nkval(tab) + toml.toml_table_narr(tab) + toml.toml_table_ntab(tab);
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        const key = toml.toml_key_in(tab, i);
        if (key == null) continue;

        if (toml.toml_table_in(tab, key)) |sub| {
            const child = if (section.len == 0)
                gpa.dupeZ(u8, std.mem.span(key)) catch {
                    setErr(out_error, &ke.KE_ERROR_OUT_OF_MEMORY, "configuration toml: section path allocation failed", @src());
                    return false;
                }
            else
                std.fmt.allocPrintSentinel(gpa, "{s}.{s}", .{ section, std.mem.span(key) }, 0) catch {
                    setErr(out_error, &ke.KE_ERROR_OUT_OF_MEMORY, "configuration toml: section path allocation failed", @src());
                    return false;
                };
            defer gpa.free(child);
            if (!walkTable(cfg, sub, child, out_error)) return false;
        } else if (toml.toml_array_in(tab, key) != null) {
            continue; // arrays deferred
        } else {
            if (!setScalar(cfg, section, key, tab, out_error)) return false;
        }
    }
    return true;
}

export fn ke_configuration_toml_load(cfg: [*c]ke.ke_configuration, path: [*c]const u8, out_error: ?*?*ke.ke_error) bool {
    if (cfg == null or path == null) {
        setErr(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "invalid argument", @src());
        return false;
    }
    // Read via libc (fopen + toml_parse_file). Zig 0.16 moved file IO behind
    // std.Io (needs an Io instance); libc is already linked and version-stable,
    // so the loader stays free of that plumbing.
    const fp = toml.fopen(path, "r");
    if (fp == null) return true; // absent/unreadable → defaults apply, not an error
    defer _ = toml.fclose(fp);

    var errbuf: [256]u8 = undefined;
    const root = toml.toml_parse_file(fp, &errbuf, errbuf.len);
    if (root == null) {
        setErr(out_error, &ke.KE_ERROR_GENERAL, &errbuf, @src());
        return false;
    }
    defer toml.toml_free(root);

    return walkTable(cfg, root, "", out_error);
}

// ── Native tests ────────────────────────────────────────────────────────────
//
// The loader is exercised against a mock ke_configuration that records each
// set_* call, so these test parse + dispatch in isolation from the real store.

const RecVal = union(enum) { int: i64, double: f64, boolean: bool, string: [:0]u8 };

const Rec = struct {
    section: [:0]u8,
    key: [:0]u8,
    value: RecVal,
};

var g_recs: std.ArrayListUnmanaged(Rec) = .empty;

fn recPush(section: [*c]const u8, key: [*c]const u8, value: RecVal) void {
    g_recs.append(gpa, .{
        .section = gpa.dupeZ(u8, std.mem.span(section)) catch unreachable,
        .key = gpa.dupeZ(u8, std.mem.span(key)) catch unreachable,
        .value = value,
    }) catch unreachable;
}

fn mockSetInt(_: [*c]ke.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: i64, _: ?*?*ke.ke_error) callconv(.c) bool {
    recPush(s, k, RecVal{ .int = v });
    return true;
}
fn mockSetDouble(_: [*c]ke.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: f64, _: ?*?*ke.ke_error) callconv(.c) bool {
    recPush(s, k, RecVal{ .double = v });
    return true;
}
fn mockSetBool(_: [*c]ke.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: bool, _: ?*?*ke.ke_error) callconv(.c) bool {
    recPush(s, k, RecVal{ .boolean = v });
    return true;
}
fn mockSetString(_: [*c]ke.ke_configuration, s: [*c]const u8, k: [*c]const u8, v: [*c]const u8, _: ?*?*ke.ke_error) callconv(.c) bool {
    recPush(s, k, RecVal{ .string = gpa.dupeZ(u8, std.mem.span(v)) catch unreachable });
    return true;
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
    g_recs.clearRetainingCapacity();
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

// Writes `data` to a file in the cwd via libc; the loader reads the same
// relative path. Using libc (not std.fs) keeps the tests off the 0.16 Io
// plumbing, matching how the loader itself opens files.
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
    try std.testing.expect(ke_configuration_toml_load(&cfg, path, null));

    try std.testing.expectEqual(@as(?i64, 2048), findInt("shadow", "resolution"));

    // Verify the other three landed with the right section/key/type/value.
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
    try std.testing.expect(ke_configuration_toml_load(&cfg, path, null));
    try std.testing.expectEqual(@as(?i64, 4), findInt("shadow.cascade", "count"));
}

test "missing file is not an error and writes nothing" {
    defer clearRecs();
    var cfg = mockConfig();
    try std.testing.expect(ke_configuration_toml_load(&cfg, "does/not/exist/Project.toml", null));
    try std.testing.expectEqual(@as(usize, 0), g_recs.items.len);
}

test "parse error returns false" {
    defer clearRecs();
    const path = "test_cfg_bad.toml";
    writeTemp(path, "this is = = not valid toml\n");
    defer _ = toml.remove(path);

    var cfg = mockConfig();
    try std.testing.expect(!ke_configuration_toml_load(&cfg, path, null));
}

test "null args rejected" {
    defer clearRecs();
    var cfg = mockConfig();
    try std.testing.expect(!ke_configuration_toml_load(null, "x", null));
    try std.testing.expect(!ke_configuration_toml_load(&cfg, null, null));
}

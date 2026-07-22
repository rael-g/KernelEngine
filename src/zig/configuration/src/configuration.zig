// ke_configuration impl (Zig) — kernel primitive. Format-agnostic typed
// settings store behind the C ABI in kernel_engine/configuration/configuration.h.
//
// Scale note: a configuration store holds tens of entries, not thousands, and is
// read at module init then written rarely (a settings menu). A growable list with
// linear search is the right shape — simpler and easier to keep correct than a
// hashed table for this workload.

const std = @import("std");

// dlopen'd by a foreign (non-Zig) host (the C# runtime) alongside many other
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack blows the small glibc static-TLS surplus once enough accumulate
// (verified: "cannot allocate memory in static TLS block"); the extra crash-
// handler stack trace it buys isn't worth an unloadable plugin.
pub const std_options: std.Options = .{ .signal_stack_size = null };
const ke = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/configuration/configuration.h");
});

const gpa = @import("heap.zig").gpa;

const NONE: u32 = std.math.maxInt(u32); // == KE_CONFIGURATION_SUBSCRIPTION_NONE

// ── Value + storage ─────────────────────────────────────────────────────────

const Value = union(enum) {
    int: i64,
    double: f64,
    boolean: bool,
    string: [:0]u8, // heap-owned
};

const Entry = struct {
    section: [:0]u8,
    key: [:0]u8,
    value: Value,
};

const Sub = struct {
    id: u32,
    section: [:0]u8,
    cb: ke.ke_configuration_change_func,
    ctx: ?*anyopaque,
    active: bool,
};

const State = struct {
    api: ke.ke_configuration, // first field: &api == &State
    entries: std.ArrayListUnmanaged(Entry),
    subs: std.ArrayListUnmanaged(Sub),
    next_sub_id: u32,
};

fn state(self: [*c]ke.ke_configuration) *State {
    return @ptrCast(@alignCast(self.*.handle));
}

// ── ke_error translation (ABI seam only) ────────────────────────────────────

fn setErr(out_error: ?*?*ke.ke_error, etype: *const ke.ke_error_type, msg: [*c]const u8, src: std.builtin.SourceLocation) void {
    ke.ke_error_set(out_error, etype, msg, src.file, @intCast(src.line), null);
}

// ── Store helpers ───────────────────────────────────────────────────────────

fn findEntry(st: *State, section: []const u8, key: []const u8) ?*Entry {
    for (st.entries.items) |*e| {
        if (std.mem.eql(u8, e.section, section) and std.mem.eql(u8, e.key, key)) return e;
    }
    return null;
}

fn freeStringPayload(e: *Entry) void {
    switch (e.value) {
        .string => |s| gpa.free(s),
        else => {},
    }
}

// Locates the (section, key) entry or appends a fresh one ready to receive a
// value. Any prior string payload of an existing entry is freed so the union can
// be reassigned. Returns null (and sets out_error) only on allocation failure.
fn upsert(st: *State, section: []const u8, key: []const u8, out_error: ?*?*ke.ke_error) ?*Entry {
    if (findEntry(st, section, key)) |e| {
        freeStringPayload(e);
        return e;
    }

    const sect = gpa.dupeZ(u8, section) catch {
        setErr(out_error, &ke.KE_ERROR_OUT_OF_MEMORY, "configuration: section allocation failed", @src());
        return null;
    };
    const k = gpa.dupeZ(u8, key) catch {
        gpa.free(sect);
        setErr(out_error, &ke.KE_ERROR_OUT_OF_MEMORY, "configuration: key allocation failed", @src());
        return null;
    };
    st.entries.append(gpa, .{ .section = sect, .key = k, .value = .{ .int = 0 } }) catch {
        gpa.free(sect);
        gpa.free(k);
        setErr(out_error, &ke.KE_ERROR_OUT_OF_MEMORY, "configuration: entry table growth failed", @src());
        return null;
    };
    return &st.entries.items[st.entries.items.len - 1];
}

// Fires every active subscription whose section matches. Called after a write.
fn notify(st: *State, section_c: [*c]const u8) void {
    const section = std.mem.span(section_c);
    for (st.subs.items) |*s| {
        if (s.active and std.mem.eql(u8, s.section, section)) {
            if (s.cb) |cb| cb(section_c, s.ctx);
        }
    }
}

// ── vtable: typed reads ─────────────────────────────────────────────────────

fn getInt(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: i64) callconv(.c) i64 {
    if (section == null or key == null) return fallback;
    if (findEntry(state(self), std.mem.span(section), std.mem.span(key))) |e| {
        switch (e.value) {
            .int => |v| return v,
            else => {},
        }
    }
    return fallback;
}

fn getDouble(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: f64) callconv(.c) f64 {
    if (section == null or key == null) return fallback;
    if (findEntry(state(self), std.mem.span(section), std.mem.span(key))) |e| {
        switch (e.value) {
            .double => |v| return v,
            else => {},
        }
    }
    return fallback;
}

fn getBool(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: bool) callconv(.c) bool {
    if (section == null or key == null) return fallback;
    if (findEntry(state(self), std.mem.span(section), std.mem.span(key))) |e| {
        switch (e.value) {
            .boolean => |v| return v,
            else => {},
        }
    }
    return fallback;
}

fn getString(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: [*c]const u8) callconv(.c) [*c]const u8 {
    if (section == null or key == null) return fallback;
    if (findEntry(state(self), std.mem.span(section), std.mem.span(key))) |e| {
        switch (e.value) {
            .string => |v| return v.ptr,
            else => {},
        }
    }
    return fallback;
}

// ── vtable: typed writes ────────────────────────────────────────────────────

fn setInt(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: i64, out_error: ?*?*ke.ke_error) callconv(.c) bool {
    if (self == null or section == null or key == null) {
        setErr(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "invalid argument", @src());
        return false;
    }
    const st = state(self);
    const e = upsert(st, std.mem.span(section), std.mem.span(key), out_error) orelse return false;
    e.value = .{ .int = value };
    notify(st, section);
    return true;
}

fn setDouble(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: f64, out_error: ?*?*ke.ke_error) callconv(.c) bool {
    if (self == null or section == null or key == null) {
        setErr(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "invalid argument", @src());
        return false;
    }
    const st = state(self);
    const e = upsert(st, std.mem.span(section), std.mem.span(key), out_error) orelse return false;
    e.value = .{ .double = value };
    notify(st, section);
    return true;
}

fn setBool(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: bool, out_error: ?*?*ke.ke_error) callconv(.c) bool {
    if (self == null or section == null or key == null) {
        setErr(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "invalid argument", @src());
        return false;
    }
    const st = state(self);
    const e = upsert(st, std.mem.span(section), std.mem.span(key), out_error) orelse return false;
    e.value = .{ .boolean = value };
    notify(st, section);
    return true;
}

fn setString(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: [*c]const u8, out_error: ?*?*ke.ke_error) callconv(.c) bool {
    if (self == null or section == null or key == null or value == null) {
        setErr(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "invalid argument", @src());
        return false;
    }
    const st = state(self);
    // Copy the new value BEFORE upsert frees any prior payload, so a failed dup
    // never leaves the entry pointing at freed memory.
    const copy = gpa.dupeZ(u8, std.mem.span(value)) catch {
        setErr(out_error, &ke.KE_ERROR_OUT_OF_MEMORY, "configuration: string value allocation failed", @src());
        return false;
    };
    const e = upsert(st, std.mem.span(section), std.mem.span(key), out_error) orelse {
        gpa.free(copy);
        return false;
    };
    e.value = .{ .string = copy };
    notify(st, section);
    return true;
}

// ── vtable: subscriptions ───────────────────────────────────────────────────

fn subscribe(self: [*c]ke.ke_configuration, section: [*c]const u8, cb: ke.ke_configuration_change_func, ctx: ?*anyopaque) callconv(.c) ke.ke_configuration_subscription {
    if (self == null or section == null or cb == null) return NONE;
    const st = state(self);
    const sec = std.mem.span(section);

    // Reuse an inactive slot before growing. Its stale section string is freed
    // here (not at unsubscribe) to keep unsubscribe a pure flag flip.
    var reuse: ?*Sub = null;
    for (st.subs.items) |*s| {
        if (!s.active) {
            reuse = s;
            break;
        }
    }

    const dup = gpa.dupeZ(u8, sec) catch return NONE;
    const id = st.next_sub_id;

    if (reuse) |slot| {
        gpa.free(slot.section);
        slot.* = .{ .id = id, .section = dup, .cb = cb, .ctx = ctx, .active = true };
    } else {
        st.subs.append(gpa, .{ .id = id, .section = dup, .cb = cb, .ctx = ctx, .active = true }) catch {
            gpa.free(dup);
            return NONE;
        };
    }
    st.next_sub_id += 1;
    return id;
}

fn unsubscribe(self: [*c]ke.ke_configuration, sub: ke.ke_configuration_subscription) callconv(.c) void {
    if (self == null or sub == NONE) return;
    const st = state(self);
    for (st.subs.items) |*s| {
        if (s.active and s.id == sub) {
            // Leave section allocated; freed on slot reuse or destroy. This keeps
            // unsubscribe a pure flag flip and avoids a double free on reuse.
            s.active = false;
            s.cb = null;
            return;
        }
    }
}

// ── vtable: teardown ────────────────────────────────────────────────────────

fn destroy(self: [*c]ke.ke_configuration) callconv(.c) void {
    if (self == null) return;
    const st = state(self);
    for (st.entries.items) |*e| {
        freeStringPayload(e);
        gpa.free(e.section);
        gpa.free(e.key);
    }
    st.entries.deinit(gpa);
    for (st.subs.items) |*s| gpa.free(s.section);
    st.subs.deinit(gpa);
    gpa.destroy(st);
}

// ── Factory ─────────────────────────────────────────────────────────────────

export fn ke_configuration_create(out_error: ?*?*ke.ke_error) ke.ke_configuration_handle {
    const st = gpa.create(State) catch {
        setErr(out_error, &ke.KE_ERROR_OUT_OF_MEMORY, "configuration: state allocation failed", @src());
        return .{ .ref = null, .destroy = null };
    };
    st.* = .{
        .api = .{
            .handle = st,
            .get_int = getInt,
            .get_double = getDouble,
            .get_bool = getBool,
            .get_string = getString,
            .set_int = setInt,
            .set_double = setDouble,
            .set_bool = setBool,
            .set_string = setString,
            .subscribe = subscribe,
            .unsubscribe = unsubscribe,
        },
        .entries = .empty,
        .subs = .empty,
        .next_sub_id = 0,
    };
    return .{ .ref = &st.api, .destroy = destroy };
}

// ── Native tests ────────────────────────────────────────────────────────────

const TestProbe = struct {
    calls: u32 = 0,
    last: [:0]const u8 = "",
};

fn testCb(section: [*c]const u8, ctx: ?*anyopaque) callconv(.c) void {
    const p: *TestProbe = @ptrCast(@alignCast(ctx));
    p.calls += 1;
    p.last = std.mem.span(section);
}

test "missing key returns caller fallback" {
    const h = ke_configuration_create(null);
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try std.testing.expectEqual(@as(i64, 1024), c.*.get_int.?(c, "shadow", "resolution", 1024));
    try std.testing.expectEqual(@as(f64, 20.0), c.*.get_double.?(c, "shadow", "frustum_size", 20.0));
    try std.testing.expectEqual(true, c.*.get_bool.?(c, "shadow", "soft", true));
    try std.testing.expectEqualStrings("shaders/", std.mem.span(c.*.get_string.?(c, "render", "shader_path", "shaders/")));
}

test "set then get round trips" {
    const h = ke_configuration_create(null);
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try std.testing.expect(c.*.set_int.?(c, "shadow", "resolution", 2048, null));
    try std.testing.expect(c.*.set_double.?(c, "shadow", "frustum_size", 30.5, null));
    try std.testing.expect(c.*.set_bool.?(c, "shadow", "soft", false, null));
    try std.testing.expect(c.*.set_string.?(c, "render", "shader_path", "res/shaders", null));

    try std.testing.expectEqual(@as(i64, 2048), c.*.get_int.?(c, "shadow", "resolution", 1024));
    try std.testing.expectEqual(@as(f64, 30.5), c.*.get_double.?(c, "shadow", "frustum_size", 20.0));
    try std.testing.expectEqual(false, c.*.get_bool.?(c, "shadow", "soft", true));
    try std.testing.expectEqualStrings("res/shaders", std.mem.span(c.*.get_string.?(c, "render", "shader_path", "shaders/")));
}

test "overwrite keeps latest" {
    const h = ke_configuration_create(null);
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try std.testing.expect(c.*.set_int.?(c, "shadow", "resolution", 512, null));
    try std.testing.expect(c.*.set_int.?(c, "shadow", "resolution", 4096, null));
    try std.testing.expectEqual(@as(i64, 4096), c.*.get_int.?(c, "shadow", "resolution", 1024));
}

test "type mismatch returns fallback" {
    const h = ke_configuration_create(null);
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try std.testing.expect(c.*.set_int.?(c, "shadow", "resolution", 2048, null));
    try std.testing.expectEqual(@as(f64, 7.0), c.*.get_double.?(c, "shadow", "resolution", 7.0));
    try std.testing.expectEqualStrings("x", std.mem.span(c.*.get_string.?(c, "shadow", "resolution", "x")));
}

test "subscriber fires only on writes to its section" {
    const h = ke_configuration_create(null);
    defer h.destroy.?(h.ref);
    const c = h.ref;
    var probe = TestProbe{};
    const sub = c.*.subscribe.?(c, "shadow", testCb, &probe);
    try std.testing.expect(sub != NONE);

    try std.testing.expect(c.*.set_int.?(c, "shadow", "resolution", 2048, null));
    try std.testing.expectEqual(@as(u32, 1), probe.calls);
    try std.testing.expectEqualStrings("shadow", probe.last);

    try std.testing.expect(c.*.set_bool.?(c, "audio", "muted", true, null));
    try std.testing.expectEqual(@as(u32, 1), probe.calls);
}

test "unsubscribe stops callbacks" {
    const h = ke_configuration_create(null);
    defer h.destroy.?(h.ref);
    const c = h.ref;
    var probe = TestProbe{};
    const sub = c.*.subscribe.?(c, "shadow", testCb, &probe);
    try std.testing.expect(c.*.set_int.?(c, "shadow", "resolution", 1, null));
    try std.testing.expectEqual(@as(u32, 1), probe.calls);

    c.*.unsubscribe.?(c, sub);
    try std.testing.expect(c.*.set_int.?(c, "shadow", "resolution", 2, null));
    try std.testing.expectEqual(@as(u32, 1), probe.calls);
}

test "multiple subscribers each fire" {
    const h = ke_configuration_create(null);
    defer h.destroy.?(h.ref);
    const c = h.ref;
    var a = TestProbe{};
    var b = TestProbe{};
    const sa = c.*.subscribe.?(c, "shadow", testCb, &a);
    const sb = c.*.subscribe.?(c, "shadow", testCb, &b);
    try std.testing.expect(sa != sb);
    try std.testing.expect(c.*.set_int.?(c, "shadow", "resolution", 2048, null));
    try std.testing.expectEqual(@as(u32, 1), a.calls);
    try std.testing.expectEqual(@as(u32, 1), b.calls);
}

test "null args rejected on write" {
    const h = ke_configuration_create(null);
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try std.testing.expect(!c.*.set_int.?(c, null, "k", 1, null));
    try std.testing.expect(!c.*.set_string.?(c, "s", "k", null, null));
}

//! The in-memory store of typed configuration values addressed by section and key, with change
//! notification per section.

const std = @import("std");

/// Sets the standard library's signal stack size option to null, so no alternate signal stack is
/// set up.
pub const std_options: std.Options = .{ .signal_stack_size = null };
const ke = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/configuration/configuration.h");
});

const heap = @import("heap");
/// The allocator every allocation in this file goes through, taken from the heap module.
const gpa = heap.gpa;

/// The sentinel `subscribe` returns on failure, and the id `unsubscribe` ignores.
const NONE: u32 = std.math.maxInt(u32);

/// The typed payload of an `Entry`. A `string` is an owned, zero-terminated copy, and the other
/// variants hold their value inline. The active variant is the type the key was last written with.
const Value = union(enum) {
    int: i64,
    double: f64,
    boolean: bool,
    string: [:0]u8,
};

/// One key of the store. Its `section` and `key` copies live as long as the entry. `value` is the
/// only part a setter changes, and when the old value is a string, its payload is freed before the
/// new value is stored.
const Entry = struct {
    section: [:0]u8,
    key: [:0]u8,
    value: Value,
};

/// One subscription slot. An inactive slot has no callback and keeps its `section` copy until
/// `subscribe` reuses it or `destroy` frees it, so `subs` never shrinks.
const Sub = struct {
    id: u32,
    section: [:0]u8,
    cb: ke.ke_configuration_change_func,
    ctx: ?*anyopaque,
    active: bool,
};

/// The store behind a handle. The handle's `ref` is the address of `api`, and `api.handle` points
/// back at this `State`, which is how every function in the table reaches the store. `entries`
/// holds at most one `Entry` per section and key. `next_sub_id` only grows, so subscription ids
/// are never repeated. Nothing is locked: every call, and every subscriber, runs on the thread
/// that makes the call.
const State = struct {
    api: ke.ke_configuration,
    entries: std.ArrayListUnmanaged(Entry),
    subs: std.ArrayListUnmanaged(Sub),
    next_sub_id: u32,
};

fn state(self: [*c]ke.ke_configuration) *State {
    return @ptrCast(@alignCast(self.*.handle));
}

fn setErr(out_error: ?*?*ke.ke_error, etype: *const ke.ke_error_type, msg: [*c]const u8, src: std.builtin.SourceLocation) void {
    ke.ke_error_set(out_error, etype, msg, src.file, @intCast(src.line), null);
}

/// The entry for this section and key, or null. The pointer is invalidated by the next append to
/// `entries`, which only `upsert` makes.
fn findEntry(st: *State, section: []const u8, key: []const u8) ?*Entry {
    for (st.entries.items) |*e| {
        if (std.mem.eql(u8, e.section, section) and std.mem.eql(u8, e.key, key)) return e;
    }
    return null;
}

/// Frees the string of `e` when it holds one. `value` still refers to the freed slice, so the
/// caller must store a new value before anything reads the entry.
fn freeStringPayload(e: *Entry) void {
    switch (e.value) {
        .string => |s| gpa.free(s),
        else => {},
    }
}

/// Returns the entry for this section and key, creating it when missing. An existing entry's string
/// payload is freed here, so the setter must store a new value before anything reads it. A new
/// entry starts with a placeholder integer that the setter always overwrites. On failure it sets an
/// out-of-memory error and returns null, and no entry is added.
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

/// Runs the callbacks of the active subscriptions on `section`, in list order, on the calling
/// thread. Each callback gets the section pointer the setter received, not a copy, so it is valid
/// only during that call.
fn notify(st: *State, section_c: [*c]const u8) void {
    const section = std.mem.span(section_c);
    for (st.subs.items) |*s| {
        if (s.active and std.mem.eql(u8, s.section, section)) {
            if (s.cb) |cb| cb(section_c, s.ctx);
        }
    }
}

/// Returns the integer stored at this section and key, or the fallback when an argument is null,
/// the key is missing, or it holds another type.
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

/// Returns the double stored at this section and key, or the fallback. The one getter that
/// converts: an integer entry is returned as a double.
fn getDouble(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: f64) callconv(.c) f64 {
    if (section == null or key == null) return fallback;
    if (findEntry(state(self), std.mem.span(section), std.mem.span(key))) |e| {
        switch (e.value) {
            .double => |v| return v,
            .int => |v| return @floatFromInt(v),
            else => {},
        }
    }
    return fallback;
}

/// Returns the boolean stored at this section and key, or the fallback when an argument is null,
/// the key is missing, or it holds another type.
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

/// Returns the string stored at this key, or the fallback. It is the entry's own string, not a
/// copy, so the pointer stops being valid at the next write to its key or at `destroy`.
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

/// Reports an invalid-argument error and returns false when an argument is null, and an
/// out-of-memory error when the entry cannot be created; the store is then as it was. Otherwise
/// the new value is stored and the subscribers of the section run, seeing it, before it returns.
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

/// As `setInt`, for a double.
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

/// As `setInt`, for a boolean.
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

/// As `setInt`, for a string, and a null value is also an invalid argument. Copies the value
/// before the entry is looked up, so a failed copy or entry creation leaves the store unchanged. A
/// successful write frees the previous string, which makes the pointer an earlier `getString`
/// returned for this key invalid.
fn setString(self: [*c]ke.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: [*c]const u8, out_error: ?*?*ke.ke_error) callconv(.c) bool {
    if (self == null or section == null or key == null or value == null) {
        setErr(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "invalid argument", @src());
        return false;
    }
    const st = state(self);
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

/// Stores the subscription in the first inactive slot, or appends a slot, and returns the id taken
/// from `next_sub_id`. A reused slot takes the new id, so the id of its previous subscription no
/// longer matches it. On failure it returns `NONE` and changes neither `subs` nor `next_sub_id`.
fn subscribe(self: [*c]ke.ke_configuration, section: [*c]const u8, cb: ke.ke_configuration_change_func, ctx: ?*anyopaque) callconv(.c) ke.ke_configuration_subscription {
    if (self == null or section == null or cb == null) return NONE;
    const st = state(self);
    const sec = std.mem.span(section);

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

/// Deactivates the slot with this id, if one is active, and clears its callback.
fn unsubscribe(self: [*c]ke.ke_configuration, sub: ke.ke_configuration_subscription) callconv(.c) void {
    if (self == null or sub == NONE) return;
    const st = state(self);
    for (st.subs.items) |*s| {
        if (s.active and s.id == sub) {
            s.active = false;
            s.cb = null;
            return;
        }
    }
}

/// After it returns, the `State`, the handle's `ref` and every pointer from `getString` are
/// invalid.
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

/// Allocates a store and returns a handle whose `ref` is its `api` table and whose `destroy` frees
/// it. On allocation failure it sets an out-of-memory error and returns a handle with null `ref`
/// and `destroy`.
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
    try std.testing.expectEqualStrings("x", std.mem.span(c.*.get_string.?(c, "shadow", "resolution", "x")));
    try std.testing.expectEqual(true, c.*.get_bool.?(c, "shadow", "resolution", true));
    try std.testing.expect(c.*.set_string.?(c, "shadow", "label", "text", null));
    try std.testing.expectEqual(@as(f64, 7.0), c.*.get_double.?(c, "shadow", "label", 7.0));
    try std.testing.expectEqual(@as(i64, 9), c.*.get_int.?(c, "shadow", "label", 9));
}

test "an integer written for a float key reads as that number, not the fallback" {
    const h = ke_configuration_create(null);
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try std.testing.expect(c.*.set_int.?(c, "shadow", "frustum_size", 30, null));
    try std.testing.expectEqual(@as(f64, 30.0), c.*.get_double.?(c, "shadow", "frustum_size", 20.0));
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

test "creating, filling and destroying a configuration leaves no block allocated" {
    const h = ke_configuration_create(null);
    const cfg = h.ref;
    try std.testing.expect(cfg.*.set_int.?(cfg, "shadow", "resolution", 2048, null));
    try std.testing.expect(cfg.*.set_string.?(cfg, "render", "shader_path", "res/shaders", null));
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

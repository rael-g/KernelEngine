//! The in-memory store of typed configuration values addressed by section and key, with change
//! notification per section.

const std = @import("std");

/// Sets the standard library's signal stack size option to null, so no alternate signal stack is
/// set up.
pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_configuration").logFn };

const abi_configuration = @import("abi_configuration");
const abi_result = @import("abi_result");

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
    cb: abi_configuration.c.ke_configuration_change_func,
    ctx: ?*anyopaque,
    active: bool,
};

/// The store behind a handle. The handle's `ref` is the address of `api`, and `api.handle` points
/// back at this `State`, which is how every function in the table reaches the store. `entries`
/// holds at most one `Entry` per section and key. `next_sub_id` only grows, so subscription ids
/// are never repeated. Nothing is locked: every call, and every subscriber, runs on the thread
/// that makes the call.
const State = struct {
    api: abi_configuration.c.ke_configuration,
    entries: std.ArrayListUnmanaged(Entry),
    subs: std.ArrayListUnmanaged(Sub),
    next_sub_id: u32,
};

fn state(self: [*c]abi_configuration.c.ke_configuration) *State {
    return @ptrCast(@alignCast(self.*.handle));
}

const R = @import("result").Result(.{});
const log = std.log.scoped(.configuration);

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
/// entry starts with a placeholder integer that the setter always overwrites. On failure no entry
/// is added.
fn upsert(st: *State, section: []const u8, key: []const u8) error{OutOfMemory}!*Entry {
    if (findEntry(st, section, key)) |e| {
        freeStringPayload(e);
        return e;
    }

    const sect = try gpa.dupeZ(u8, section);
    errdefer gpa.free(sect);
    const k = try gpa.dupeZ(u8, key);
    errdefer gpa.free(k);
    try st.entries.append(gpa, .{ .section = sect, .key = k, .value = .{ .int = 0 } });
    return &st.entries.items[st.entries.items.len - 1];
}

/// Stores `value` under the key through `upsert`, then runs the section's subscribers.
fn store(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: Value) abi_result.c.ke_result {
    const st = state(self);
    const e = upsert(st, std.mem.span(section), std.mem.span(key)) catch {
        log.warn("storing {s}.{s} failed: out of memory", .{ section, key });
        return R.code(error.OutOfMemory);
    };
    e.value = value;
    notify(st, section);
    return R.ok;
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

/// Lists the children of `section` from the entries' sections, deduplicated in first-seen order;
/// each name is copied into a NUL-terminated buffer for the duration of its callback.
fn forEachChild(self: [*c]abi_configuration.c.ke_configuration, section_c: [*c]const u8, each: abi_configuration.c.ke_configuration_child_func, ctx: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    if (self == null or section_c == null) return R.code(error.InvalidArgument);
    const cb = each orelse return R.code(error.InvalidArgument);
    const st = state(self);
    const parent = std.mem.span(section_c);
    var seen: std.ArrayListUnmanaged([]const u8) = .empty;
    defer seen.deinit(gpa);
    for (st.entries.items) |e| {
        const child = childOf(parent, e.section) orelse continue;
        var known = false;
        for (seen.items) |n| known = known or std.mem.eql(u8, n, child);
        if (known) continue;
        seen.append(gpa, child) catch return R.code(error.OutOfMemory);
        const name = gpa.dupeZ(u8, child) catch return R.code(error.OutOfMemory);
        defer gpa.free(name);
        cb(name.ptr, ctx);
    }
    return R.ok;
}

fn childOf(parent: []const u8, section: []const u8) ?[]const u8 {
    const rest = if (parent.len == 0) section else blk: {
        if (section.len <= parent.len + 1 or !std.mem.startsWith(u8, section, parent) or section[parent.len] != '.') return null;
        break :blk section[parent.len + 1 ..];
    };
    if (rest.len == 0) return null;
    const end = std.mem.indexOfScalar(u8, rest, '.') orelse rest.len;
    return rest[0..end];
}

/// Returns the integer stored at this section and key, or the fallback when an argument is null,
/// the key is missing, or it holds another type.
fn getInt(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: i64) callconv(.c) i64 {
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
fn getDouble(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: f64) callconv(.c) f64 {
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
fn getBool(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: bool) callconv(.c) bool {
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
fn getString(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: [*c]const u8) callconv(.c) [*c]const u8 {
    if (section == null or key == null) return fallback;
    if (findEntry(state(self), std.mem.span(section), std.mem.span(key))) |e| {
        switch (e.value) {
            .string => |v| return v.ptr,
            else => {},
        }
    }
    return fallback;
}

/// Fails with invalid argument when an argument is null, and out of memory when the entry cannot be
/// created; the store is then as it was. Otherwise the new value is stored and the subscribers of
/// the section run, seeing it, before it returns.
fn setInt(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: i64) callconv(.c) abi_result.c.ke_result {
    if (self == null or section == null or key == null) return R.code(error.InvalidArgument);
    return store(self, section, key, .{ .int = value });
}

/// As `setInt`, for a double.
fn setDouble(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: f64) callconv(.c) abi_result.c.ke_result {
    if (self == null or section == null or key == null) return R.code(error.InvalidArgument);
    return store(self, section, key, .{ .double = value });
}

/// As `setInt`, for a boolean.
fn setBool(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: bool) callconv(.c) abi_result.c.ke_result {
    if (self == null or section == null or key == null) return R.code(error.InvalidArgument);
    return store(self, section, key, .{ .boolean = value });
}

/// As `setInt`, for a string, and a null value is also an invalid argument. Copies the value
/// before the entry is looked up, so a failed copy or entry creation leaves the store unchanged. A
/// successful write frees the previous string, which makes the pointer an earlier `getString`
/// returned for this key invalid.
fn setString(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: [*c]const u8) callconv(.c) abi_result.c.ke_result {
    if (self == null or section == null or key == null or value == null) return R.code(error.InvalidArgument);
    const copy = gpa.dupeZ(u8, std.mem.span(value)) catch {
        log.warn("storing {s}.{s} failed: out of memory", .{ section, key });
        return R.code(error.OutOfMemory);
    };
    const result = store(self, section, key, .{ .string = copy });
    if (result != R.ok) gpa.free(copy);
    return result;
}

/// Stores the subscription in the first inactive slot, or appends a slot, and returns the id taken
/// from `next_sub_id`. A reused slot takes the new id, so the id of its previous subscription no
/// longer matches it. On failure it returns `NONE` and changes neither `subs` nor `next_sub_id`.
fn subscribe(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, cb: abi_configuration.c.ke_configuration_change_func, ctx: ?*anyopaque) callconv(.c) abi_configuration.c.ke_configuration_subscription {
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
fn unsubscribe(self: [*c]abi_configuration.c.ke_configuration, sub: abi_configuration.c.ke_configuration_subscription) callconv(.c) void {
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
fn destroy(self: [*c]abi_configuration.c.ke_configuration) callconv(.c) void {
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

/// Writes `value` into the integer field at `at`, whose width is `size`; false for a width no
/// integer has.
fn writeInt(at: [*]u8, size: u32, value: i64) bool {
    switch (size) {
        1 => std.mem.writeInt(u8, at[0..1], @truncate(@as(u64, @bitCast(value))), .little),
        2 => std.mem.writeInt(u16, at[0..2], @truncate(@as(u64, @bitCast(value))), .little),
        4 => std.mem.writeInt(u32, at[0..4], @truncate(@as(u64, @bitCast(value))), .little),
        8 => std.mem.writeInt(u64, at[0..8], @bitCast(value), .little),
        else => return false,
    }
    return true;
}

/// Writes `value` into the float or double field at `at`; false when the field's size is neither.
fn writeReal(at: [*]u8, field: *const abi_configuration.c.ke_config_field, value: f64) bool {
    if (field.type == abi_configuration.c.KE_CONFIG_FLOAT and field.size == @sizeOf(f32)) {
        const v: f32 = @floatCast(value);
        @memcpy(at[0..@sizeOf(f32)], std.mem.asBytes(&v));
        return true;
    }
    if (field.type == abi_configuration.c.KE_CONFIG_DOUBLE and field.size == @sizeOf(f64)) {
        @memcpy(at[0..@sizeOf(f64)], std.mem.asBytes(&value));
        return true;
    }
    return false;
}

fn writeBool(at: [*]u8, field: *const abi_configuration.c.ke_config_field, value: bool) bool {
    if (field.size != @sizeOf(bool)) return false;
    at[0] = @intFromBool(value);
    return true;
}

fn writeString(at: [*]u8, field: *const abi_configuration.c.ke_config_field, value: [*c]const u8) bool {
    if (field.size != @sizeOf([*c]const u8)) return false;
    @memcpy(at[0..@sizeOf([*c]const u8)], std.mem.asBytes(&value));
    return true;
}

fn writeDefault(at: [*]u8, field: *const abi_configuration.c.ke_config_field) bool {
    const d = field.default_value;
    return switch (field.type) {
        abi_configuration.c.KE_CONFIG_INT => writeInt(at, field.size, d.i),
        abi_configuration.c.KE_CONFIG_FLOAT, abi_configuration.c.KE_CONFIG_DOUBLE => writeReal(at, field, d.d),
        abi_configuration.c.KE_CONFIG_BOOL => writeBool(at, field, d.b),
        abi_configuration.c.KE_CONFIG_STRING => writeString(at, field, d.s),
        else => false,
    };
}

/// Writes the entry's value over the default, or logs and keeps the default when the field cannot
/// take that type.
fn writeStored(at: [*]u8, field: *const abi_configuration.c.ke_config_field, section: []const u8, value: Value) void {
    const written = switch (field.type) {
        abi_configuration.c.KE_CONFIG_INT => switch (value) {
            .int => |v| writeInt(at, field.size, v),
            else => false,
        },
        abi_configuration.c.KE_CONFIG_FLOAT, abi_configuration.c.KE_CONFIG_DOUBLE => switch (value) {
            .double => |v| writeReal(at, field, v),
            .int => |v| writeReal(at, field, @floatFromInt(v)),
            else => false,
        },
        abi_configuration.c.KE_CONFIG_BOOL => switch (value) {
            .boolean => |v| writeBool(at, field, v),
            else => false,
        },
        abi_configuration.c.KE_CONFIG_STRING => switch (value) {
            .string => |v| writeString(at, field, v.ptr),
            else => false,
        },
        else => false,
    };
    if (!written) log.warn("{s}.{s} holds a {t}, which the field cannot take; the default stands", .{ section, field.key.?, value });
}

/// Slot `fill`. Reads the store and writes only into `out_config`, so no subscriber runs.
fn fill(self: [*c]abi_configuration.c.ke_configuration, section_c: [*c]const u8, fields: [*c]const abi_configuration.c.ke_config_field, field_count: u32, out_config: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    if (self == null or section_c == null or out_config == null) return R.code(error.InvalidArgument);
    if (fields == null and field_count != 0) return R.code(error.InvalidArgument);
    const st = state(self);
    const section = std.mem.span(section_c);
    const base: [*]u8 = @ptrCast(out_config.?);
    for (0..field_count) |i| {
        const field: *const abi_configuration.c.ke_config_field = @ptrCast(fields + i);
        const at = base + field.offset;
        const key = field.key orelse return R.code(error.InvalidArgument);
        if (!writeDefault(at, field)) return R.code(error.InvalidArgument);
        if (findEntry(st, section, std.mem.span(key))) |e| writeStored(at, field, section, e.value);
    }
    return R.ok;
}

/// Allocates a store and writes a handle whose `ref` is its `api` table and whose `destroy` frees
/// it. Fails with out of memory, leaving the handle zeroed.
export fn ke_configuration_create(out_store: ?*abi_configuration.c.ke_configuration_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_store orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const st = gpa.create(State) catch {
        log.warn("creating the configuration store failed: out of memory", .{});
        return R.code(error.OutOfMemory);
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
            .fill = fill,
            .for_each_child = forEachChild,
        },
        .entries = .empty,
        .subs = .empty,
        .next_sub_id = 0,
    };
    out.* = .{ .ref = &st.api, .destroy = destroy };
    return R.ok;
}

const FilledConfig = extern struct {
    count: u32,
    scale: f32,
    enabled: bool,
    title: [*c]const u8,
};

const filled_fields = [_]abi_configuration.c.ke_config_field{
    .{ .key = "count", .type = abi_configuration.c.KE_CONFIG_INT, .offset = @offsetOf(FilledConfig, "count"), .size = 4, .default_value = .{ .i = 3 } },
    .{ .key = "scale", .type = abi_configuration.c.KE_CONFIG_FLOAT, .offset = @offsetOf(FilledConfig, "scale"), .size = 4, .default_value = .{ .d = -9.5 } },
    .{ .key = "enabled", .type = abi_configuration.c.KE_CONFIG_BOOL, .offset = @offsetOf(FilledConfig, "enabled"), .size = 1, .default_value = .{ .b = true } },
    .{ .key = "title", .type = abi_configuration.c.KE_CONFIG_STRING, .offset = @offsetOf(FilledConfig, "title"), .size = @sizeOf([*c]const u8), .default_value = .{ .s = "untitled" } },
};

const TestProbe = struct {
    calls: u32 = 0,
    last: [:0]const u8 = "",
};

fn testCb(section: [*c]const u8, ctx: ?*anyopaque) callconv(.c) void {
    const p: *TestProbe = @ptrCast(@alignCast(ctx));
    p.calls += 1;
    p.last = std.mem.span(section);
}

fn madeStore() !abi_configuration.c.ke_configuration_handle {
    var h: abi_configuration.c.ke_configuration_handle = undefined;
    try R.check(ke_configuration_create(&h));
    return h;
}

test "missing key returns caller fallback" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try std.testing.expectEqual(@as(i64, 1024), c.?.get_int.?(c, "shadow", "resolution", 1024));
    try std.testing.expectEqual(@as(f64, 20.0), c.?.get_double.?(c, "shadow", "frustum_size", 20.0));
    try std.testing.expectEqual(true, c.?.get_bool.?(c, "shadow", "soft", true));
    try std.testing.expectEqualStrings("shaders/", std.mem.span(c.?.get_string.?(c, "render", "shader_path", "shaders/").?));
}

test "set then get round trips" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try R.check(c.?.set_int.?(c, "shadow", "resolution", 2048));
    try R.check(c.?.set_double.?(c, "shadow", "frustum_size", 30.5));
    try R.check(c.?.set_bool.?(c, "shadow", "soft", false));
    try R.check(c.?.set_string.?(c, "render", "shader_path", "res/shaders"));

    try std.testing.expectEqual(@as(i64, 2048), c.?.get_int.?(c, "shadow", "resolution", 1024));
    try std.testing.expectEqual(@as(f64, 30.5), c.?.get_double.?(c, "shadow", "frustum_size", 20.0));
    try std.testing.expectEqual(false, c.?.get_bool.?(c, "shadow", "soft", true));
    try std.testing.expectEqualStrings("res/shaders", std.mem.span(c.?.get_string.?(c, "render", "shader_path", "shaders/").?));
}

test "overwrite keeps latest" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try R.check(c.?.set_int.?(c, "shadow", "resolution", 512));
    try R.check(c.?.set_int.?(c, "shadow", "resolution", 4096));
    try std.testing.expectEqual(@as(i64, 4096), c.?.get_int.?(c, "shadow", "resolution", 1024));
}

test "type mismatch returns fallback" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try R.check(c.?.set_int.?(c, "shadow", "resolution", 2048));
    try std.testing.expectEqualStrings("x", std.mem.span(c.?.get_string.?(c, "shadow", "resolution", "x").?));
    try std.testing.expectEqual(true, c.?.get_bool.?(c, "shadow", "resolution", true));
    try R.check(c.?.set_string.?(c, "shadow", "label", "text"));
    try std.testing.expectEqual(@as(f64, 7.0), c.?.get_double.?(c, "shadow", "label", 7.0));
    try std.testing.expectEqual(@as(i64, 9), c.?.get_int.?(c, "shadow", "label", 9));
}

test "an integer written for a float key reads as that number, not the fallback" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try R.check(c.?.set_int.?(c, "shadow", "frustum_size", 30));
    try std.testing.expectEqual(@as(f64, 30.0), c.?.get_double.?(c, "shadow", "frustum_size", 20.0));
}

test "subscriber fires only on writes to its section" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    var probe = TestProbe{};
    const sub = c.?.subscribe.?(c, "shadow", testCb, &probe);
    try std.testing.expect(sub != NONE);

    try R.check(c.?.set_int.?(c, "shadow", "resolution", 2048));
    try std.testing.expectEqual(@as(u32, 1), probe.calls);
    try std.testing.expectEqualStrings("shadow", probe.last);

    try R.check(c.?.set_bool.?(c, "audio", "muted", true));
    try std.testing.expectEqual(@as(u32, 1), probe.calls);
}

test "unsubscribe stops callbacks" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    var probe = TestProbe{};
    const sub = c.?.subscribe.?(c, "shadow", testCb, &probe);
    try R.check(c.?.set_int.?(c, "shadow", "resolution", 1));
    try std.testing.expectEqual(@as(u32, 1), probe.calls);

    c.?.unsubscribe.?(c, sub);
    try R.check(c.?.set_int.?(c, "shadow", "resolution", 2));
    try std.testing.expectEqual(@as(u32, 1), probe.calls);
}

test "multiple subscribers each fire" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    var a = TestProbe{};
    var b = TestProbe{};
    const sa = c.?.subscribe.?(c, "shadow", testCb, &a);
    const sb = c.?.subscribe.?(c, "shadow", testCb, &b);
    try std.testing.expect(sa != sb);
    try R.check(c.?.set_int.?(c, "shadow", "resolution", 2048));
    try std.testing.expectEqual(@as(u32, 1), a.calls);
    try std.testing.expectEqual(@as(u32, 1), b.calls);
}

test "null args rejected on write" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try std.testing.expectError(error.InvalidArgument, R.check(c.?.set_int.?(c, null, "k", 1)));
    try std.testing.expectError(error.InvalidArgument, R.check(c.?.set_string.?(c, "s", "k", null)));
}

test "filling from an empty section writes every default" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    var config: FilledConfig = undefined;
    try R.check(h.ref.?.fill.?(h.ref, "app", &filled_fields, filled_fields.len, &config));
    try std.testing.expectEqual(@as(u32, 3), config.count);
    try std.testing.expectEqual(@as(f32, -9.5), config.scale);
    try std.testing.expect(config.enabled);
    try std.testing.expectEqualStrings("untitled", std.mem.span(config.title));
}

test "filling lays the stored values over the defaults and an integer reaches a float field" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    try R.check(h.ref.?.set_int.?(h.ref, "app", "scale", 2));
    try R.check(h.ref.?.set_bool.?(h.ref, "app", "enabled", false));
    try R.check(h.ref.?.set_string.?(h.ref, "app", "title", "pong"));
    var config: FilledConfig = undefined;
    try R.check(h.ref.?.fill.?(h.ref, "app", &filled_fields, filled_fields.len, &config));
    try std.testing.expectEqual(@as(u32, 3), config.count);
    try std.testing.expectEqual(@as(f32, 2.0), config.scale);
    try std.testing.expect(!config.enabled);
    try std.testing.expectEqualStrings("pong", std.mem.span(config.title));
}

test "a key of a type its field cannot take leaves the default" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    try R.check(h.ref.?.set_string.?(h.ref, "app", "count", "many"));
    var config: FilledConfig = undefined;
    try R.check(h.ref.?.fill.?(h.ref, "app", &filled_fields, filled_fields.len, &config));
    try std.testing.expectEqual(@as(u32, 3), config.count);
}

test "filling with a null section, table or struct is refused" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    var config: FilledConfig = undefined;
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.?.fill.?(h.ref, null, &filled_fields, filled_fields.len, &config)));
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.?.fill.?(h.ref, "app", null, 1, &config)));
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.?.fill.?(h.ref, "app", &filled_fields, filled_fields.len, null)));
}

test "creating, filling and destroying a configuration leaves no block allocated" {
    const h = try madeStore();
    const cfg = h.ref;
    try R.check(cfg.?.set_int.?(cfg, "shadow", "resolution", 2048));
    try R.check(cfg.?.set_string.?(cfg, "render", "shader_path", "res/shaders"));
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

const ChildList = struct {
    names: [8][16]u8 = undefined,
    count: usize = 0,

    fn add(name: [*c]const u8, ctx: ?*anyopaque) callconv(.c) void {
        const l: *ChildList = @ptrCast(@alignCast(ctx));
        const span = std.mem.span(name);
        @memcpy(l.names[l.count][0..span.len], span);
        l.names[l.count][span.len] = 0;
        l.count += 1;
    }

    fn at(l: *const ChildList, i: usize) []const u8 {
        return std.mem.sliceTo(&l.names[i], 0);
    }
};

test "the children of a section are listed once each, in the order their first key was stored" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try R.check(c.?.set_int.?(c, "input.map.Menu", "priority", 10));
    try R.check(c.?.set_string.?(c, "input.map.Game.action.Jump", "type", "Button"));
    try R.check(c.?.set_int.?(c, "input.map.Menu", "enabled", 0));
    try R.check(c.?.set_string.?(c, "input.mapping", "x", "y"));
    var maps: ChildList = .{};
    try R.check(c.?.for_each_child.?(c, "input.map", ChildList.add, &maps));
    try std.testing.expectEqual(@as(usize, 2), maps.count);
    try std.testing.expectEqualStrings("Menu", maps.at(0));
    try std.testing.expectEqualStrings("Game", maps.at(1));
    var top: ChildList = .{};
    try R.check(c.?.for_each_child.?(c, "", ChildList.add, &top));
    try std.testing.expectEqual(@as(usize, 1), top.count);
    try std.testing.expectEqualStrings("input", top.at(0));
    try std.testing.expectError(error.InvalidArgument, R.check(c.?.for_each_child.?(c, null, ChildList.add, &top)));
}

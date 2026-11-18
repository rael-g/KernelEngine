//! The in-memory store of typed configuration values addressed by section and key, and the view of
//! one section as the settings a part is created with.

const std = @import("std");

/// Sets the standard library's signal stack size option to null, so no alternate signal stack is
/// set up.
pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_configuration").logFn };

const abi_configuration = @import("abi_configuration");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");

const heap = @import("heap");
/// The allocator every allocation in this file goes through, taken from the heap module.
const gpa = heap.gpa;

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

/// The store behind a handle. The handle's `ref` is the address of `api`, and `api.handle` points
/// back at this `State`, which is how every function in the table reaches the store. `entries`
/// holds at most one `Entry` per section and key. `views` holds one `View` per section asked for,
/// each allocated once so the settings pointer handed out stays valid until `destroy`. Nothing is
/// locked: every call runs on the thread that makes the call.
const State = struct {
    api: abi_configuration.c.ke_configuration,
    entries: std.ArrayListUnmanaged(Entry),
    views: std.ArrayListUnmanaged(*View),
};

/// One section seen as `ke_settings`, made by `section`. `api.handle` points back at the view; every
/// read looks `store` up under `name` when it is made, so a write after the view was taken is seen.
const View = struct {
    api: abi_settings.c.ke_settings,
    store: *State,
    name: [:0]u8,
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

/// Stores `value` under the key through `upsert`.
fn store(self: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, value: Value) abi_result.c.ke_result {
    const st = state(self);
    const e = upsert(st, std.mem.span(section), std.mem.span(key)) catch {
        log.warn("storing {s}.{s} failed: out of memory", .{ section, key });
        return R.code(error.OutOfMemory);
    };
    e.value = value;
    return R.ok;
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
/// created; the store is then as it was.
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

fn viewOf(self: ?*abi_settings.c.ke_settings) ?*View {
    const api = self orelse return null;
    return @ptrCast(@alignCast(api.handle orelse return null));
}

fn viewEntry(self: ?*abi_settings.c.ke_settings, key: ?[*:0]const u8) error{ InvalidArgument, NotFound }!*Entry {
    const v = viewOf(self) orelse return error.InvalidArgument;
    const k = key orelse return error.InvalidArgument;
    return findEntry(v.store, v.name, std.mem.span(k)) orelse error.NotFound;
}

/// Slot `get_bool` of a section's settings.
fn settingsGetBool(self: ?*abi_settings.c.ke_settings, key: ?[*:0]const u8, out_value: ?*bool) callconv(.c) abi_result.c.ke_result {
    const out = out_value orelse return R.code(error.InvalidArgument);
    const e = viewEntry(self, key) catch |err| return R.code(err);
    switch (e.value) {
        .boolean => |b| out.* = b,
        else => return R.code(error.InvalidArgument),
    }
    return R.ok;
}

/// Slot `get_int` of a section's settings.
fn settingsGetInt(self: ?*abi_settings.c.ke_settings, key: ?[*:0]const u8, out_value: ?*i64) callconv(.c) abi_result.c.ke_result {
    const out = out_value orelse return R.code(error.InvalidArgument);
    const e = viewEntry(self, key) catch |err| return R.code(err);
    switch (e.value) {
        .int => |i| out.* = i,
        else => return R.code(error.InvalidArgument),
    }
    return R.ok;
}

/// Slot `get_double` of a section's settings; an integer entry is read as its number.
fn settingsGetDouble(self: ?*abi_settings.c.ke_settings, key: ?[*:0]const u8, out_value: ?*f64) callconv(.c) abi_result.c.ke_result {
    const out = out_value orelse return R.code(error.InvalidArgument);
    const e = viewEntry(self, key) catch |err| return R.code(err);
    switch (e.value) {
        .double => |d| out.* = d,
        .int => |i| out.* = @floatFromInt(i),
        else => return R.code(error.InvalidArgument),
    }
    return R.ok;
}

/// Slot `get_string` of a section's settings: the entry's own string, valid until its key is
/// written again or the store is destroyed.
fn settingsGetString(self: ?*abi_settings.c.ke_settings, key: ?[*:0]const u8, out_value: ?*?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    const out = out_value orelse return R.code(error.InvalidArgument);
    const e = viewEntry(self, key) catch |err| return R.code(err);
    switch (e.value) {
        .string => |str| out.* = str.ptr,
        else => return R.code(error.InvalidArgument),
    }
    return R.ok;
}

/// Slot `for_each_key` of a section's settings: the keys of the entries whose section is exactly
/// the view's, in the order they were first stored.
fn settingsForEachKey(self: ?*abi_settings.c.ke_settings, each: abi_settings.c.ke_settings_key_func, ctx: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const v = viewOf(self) orelse return R.code(error.InvalidArgument);
    const cb = each orelse return R.code(error.InvalidArgument);
    for (v.store.entries.items) |e| {
        if (std.mem.eql(u8, e.section, v.name)) cb(e.key.ptr, ctx);
    }
    return R.ok;
}

/// Slot `section`. The view of a section is made the first time it is asked for and handed out
/// again afterwards.
fn sectionView(self: ?*abi_configuration.c.ke_configuration, name_c: ?[*:0]const u8, out_settings: ?*?*abi_settings.c.ke_settings) callconv(.c) abi_result.c.ke_result {
    const out = out_settings orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self_ok = self orelse return R.code(error.InvalidArgument);
    const st = state(self_ok);
    const name = std.mem.span(name_c orelse return R.code(error.InvalidArgument));
    for (st.views.items) |v| {
        if (std.mem.eql(u8, v.name, name)) {
            out.* = &v.api;
            return R.ok;
        }
    }
    const v = makeView(st, name) catch {
        log.warn("viewing section {s} failed: out of memory", .{name});
        return R.code(error.OutOfMemory);
    };
    out.* = &v.api;
    return R.ok;
}

fn makeView(st: *State, name: []const u8) error{OutOfMemory}!*View {
    const v = try gpa.create(View);
    errdefer gpa.destroy(v);
    const owned = try gpa.dupeZ(u8, name);
    errdefer gpa.free(owned);
    v.* = .{
        .api = .{
            .handle = v,
            .get_bool = settingsGetBool,
            .get_int = settingsGetInt,
            .get_double = settingsGetDouble,
            .get_string = settingsGetString,
            .for_each_key = settingsForEachKey,
        },
        .store = st,
        .name = owned,
    };
    try st.views.append(gpa, v);
    return v;
}

/// After it returns, the `State`, the handle's `ref`, every settings view and every pointer from
/// `getString` are invalid.
fn destroy(self: [*c]abi_configuration.c.ke_configuration) callconv(.c) void {
    if (self == null) return;
    const st = state(self);
    for (st.entries.items) |*e| {
        freeStringPayload(e);
        gpa.free(e.section);
        gpa.free(e.key);
    }
    st.entries.deinit(gpa);
    for (st.views.items) |v| {
        gpa.free(v.name);
        gpa.destroy(v);
    }
    st.views.deinit(gpa);
    gpa.destroy(st);
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
            .section = sectionView,
            .for_each_child = forEachChild,
        },
        .entries = .empty,
        .views = .empty,
    };
    out.* = .{ .ref = &st.api, .destroy = destroy };
    return R.ok;
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

fn settingsOf(cfg: ?*abi_configuration.c.ke_configuration, name: [*:0]const u8) !*abi_settings.c.ke_settings {
    var out: ?*abi_settings.c.ke_settings = null;
    try R.check(cfg.?.section.?(cfg, name, &out));
    return out.?;
}

test "a section read as settings gives each key of it by type, and nothing of other sections" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const cfg = h.ref;
    try R.check(cfg.?.set_int.?(cfg, "render.shadow", "resolution", 2048));
    try R.check(cfg.?.set_bool.?(cfg, "render.shadow", "soft", true));
    try R.check(cfg.?.set_string.?(cfg, "render.shadow", "mode", "pcf"));
    try R.check(cfg.?.set_int.?(cfg, "render", "resolution", 7));
    const st = try settingsOf(cfg, "render.shadow");

    var i: i64 = 0;
    try R.check(st.get_int.?(st, "resolution", &i));
    try std.testing.expectEqual(@as(i64, 2048), i);
    var d: f64 = 0;
    try R.check(st.get_double.?(st, "resolution", &d));
    try std.testing.expectEqual(@as(f64, 2048), d);
    var b = false;
    try R.check(st.get_bool.?(st, "soft", &b));
    try std.testing.expect(b);
    var text: ?[*:0]const u8 = null;
    try R.check(st.get_string.?(st, "mode", &text));
    try std.testing.expectEqualStrings("pcf", std.mem.span(text.?));
    try std.testing.expectError(error.NotFound, R.check(st.get_int.?(st, "missing", &i)));
    try std.testing.expectError(error.InvalidArgument, R.check(st.get_bool.?(st, "resolution", &b)));
}

const KeyCount = struct {
    count: u32 = 0,

    fn add(_: ?[*:0]const u8, ctx: ?*anyopaque) callconv(.c) void {
        const k: *KeyCount = @ptrCast(@alignCast(ctx));
        k.count += 1;
    }
};

test "a section's settings list its own keys, see a later write, and are handed out once per section" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const cfg = h.ref;
    const empty = try settingsOf(cfg, "ecs");
    var keys: KeyCount = .{};
    try R.check(empty.for_each_key.?(empty, KeyCount.add, &keys));
    try std.testing.expectEqual(@as(u32, 0), keys.count);

    try R.check(cfg.?.set_int.?(cfg, "ecs", "reserved_id_capacity", 64));
    try R.check(cfg.?.set_int.?(cfg, "ecs.inner", "x", 1));
    try R.check(empty.for_each_key.?(empty, KeyCount.add, &keys));
    try std.testing.expectEqual(@as(u32, 1), keys.count);
    try std.testing.expectEqual(empty, try settingsOf(cfg, "ecs"));
}

test "null args rejected on write" {
    const h = try madeStore();
    defer h.destroy.?(h.ref);
    const c = h.ref;
    try std.testing.expectError(error.InvalidArgument, R.check(c.?.set_int.?(c, null, "k", 1)));
    try std.testing.expectError(error.InvalidArgument, R.check(c.?.set_string.?(c, "s", "k", null)));
}

test "creating, writing and destroying a configuration leaves no block allocated" {
    const h = try madeStore();
    const cfg = h.ref;
    try R.check(cfg.?.set_int.?(cfg, "shadow", "resolution", 2048));
    try R.check(cfg.?.set_string.?(cfg, "render", "shader_path", "res/shaders"));
    _ = try settingsOf(cfg, "shadow");
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

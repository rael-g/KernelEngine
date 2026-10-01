const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const heap = @import("heap");
const gpa = heap.gpa;

const c = @cImport({
    @cInclude("kernel_engine/resource_cache/resource_cache.h");
    @cInclude("kernel_engine/resource_cache/default/resource_cache_default_create.h");
});

const E = @import("kerror").Errors(c);

fn hashString(str: ?[*:0]const u8) u64 {
    const s = str orelse return 0;
    var h: u64 = 5381;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        h = h *% 33 ^ @as(u64, s[i]);
    }
    return h;
}

const RC_EMPTY: u64 = 0;
const RC_TOMBSTONE: u64 = std.math.maxInt(u64);
const HANDLE_NONE: c.ke_resource_handle = std.math.maxInt(u32);

const Slot = struct {
    key: u64 = 0,
    refcount: u32 = 0,
    handle: u32 = 0,
};

const Table = struct {
    slots: []Slot,
    capacity: usize,
    occupied: usize,
    active: usize,

    fn init(initial_capacity: usize) ?Table {
        const slots = gpa.alloc(Slot, initial_capacity) catch return null;
        @memset(slots, .{});
        return .{ .slots = slots, .capacity = initial_capacity, .occupied = 0, .active = 0 };
    }

    fn deinit(t: *Table) void {
        if (t.slots.len != 0) gpa.free(t.slots);
        t.slots = &.{};
        t.capacity = 0;
        t.occupied = 0;
        t.active = 0;
    }

    fn probe(t: *const Table, key: u64, found: *bool) usize {
        const mask = t.capacity - 1;
        var index = @as(usize, @intCast(key & mask));
        var first_tombstone: usize = std.math.maxInt(usize);
        var i: usize = 0;
        while (i < t.capacity) : (i += 1) {
            const s = &t.slots[index];
            if (s.key == RC_EMPTY) {
                found.* = false;
                return if (first_tombstone != std.math.maxInt(usize)) first_tombstone else index;
            }
            if (s.key == RC_TOMBSTONE) {
                if (first_tombstone == std.math.maxInt(usize)) first_tombstone = index;
            } else if (s.key == key) {
                found.* = true;
                return index;
            }
            index = (index + 1) & mask;
        }
        found.* = false;
        return if (first_tombstone != std.math.maxInt(usize)) first_tombstone else 0;
    }

    fn reserve(t: *Table) bool {
        if ((t.occupied + 1) * 10 < t.capacity * 7) return true;
        return t.rehash(t.capacity * 2);
    }

    fn rehash(t: *Table, new_capacity: usize) bool {
        const old_slots = t.slots;
        const new_slots = gpa.alloc(Slot, new_capacity) catch return false;
        @memset(new_slots, .{});

        t.slots = new_slots;
        t.capacity = new_capacity;
        t.occupied = 0;
        t.active = 0;

        for (old_slots) |s| {
            if (s.key == RC_EMPTY or s.key == RC_TOMBSTONE) continue;
            var found = false;
            const idx = t.probe(s.key, &found);
            t.slots[idx] = s;
            t.occupied += 1;
            t.active += 1;
        }
        gpa.free(old_slots);
        return true;
    }
};

fn keyFromHandle(h: c.ke_resource_handle) u64 {
    return @as(u64, h) + 1;
}

fn keyFromPath(path: ?[*:0]const u8) u64 {
    const k = hashString(path);
    if (k == RC_EMPTY) return 1;
    if (k == RC_TOMBSTONE) return RC_TOMBSTONE - 1;
    return k;
}

const State = struct {
    api: c.ke_resource_cache,
    destroy_fn: c.ke_resource_destroy_func,
    destroy_ctx: ?*anyopaque,
    resources: Table,
    paths: Table,
};

fn stateOf(self: *c.ke_resource_cache) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn vtRegister(self: ?*c.ke_resource_cache, handle: c.ke_resource_handle, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    if (self == null or handle == HANDLE_NONE) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self.?);
    if (!s.resources.reserve()) return false;

    var found = false;
    const key = keyFromHandle(handle);
    const idx = s.resources.probe(key, &found);
    if (found) {
        E.fail(out_error, .already_exists, "handle already registered", @src());
        return false;
    }

    if (s.resources.slots[idx].key == RC_EMPTY) s.resources.occupied += 1;
    s.resources.active += 1;
    s.resources.slots[idx] = .{ .key = key, .refcount = 1, .handle = handle };
    return true;
}

fn vtRetain(self: ?*c.ke_resource_cache, handle: c.ke_resource_handle, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    if (self == null or handle == HANDLE_NONE) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self.?);
    var found = false;
    const idx = s.resources.probe(keyFromHandle(handle), &found);
    if (!found) {
        E.fail(out_error, .not_found, "handle not found", @src());
        return false;
    }
    s.resources.slots[idx].refcount += 1;
    return true;
}

fn evictPathsForHandle(s: *State, handle: c.ke_resource_handle) void {
    for (s.paths.slots) |*p| {
        if (p.key != RC_EMPTY and p.key != RC_TOMBSTONE and p.handle == handle) {
            p.key = RC_TOMBSTONE;
            s.paths.active -= 1;
        }
    }
}

fn vtRelease(self: ?*c.ke_resource_cache, handle: c.ke_resource_handle, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    if (self == null or handle == HANDLE_NONE) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self.?);
    var found = false;
    const idx = s.resources.probe(keyFromHandle(handle), &found);
    if (!found) {
        E.fail(out_error, .not_found, "handle not found", @src());
        return false;
    }

    const slot_ref = &s.resources.slots[idx];
    if (slot_ref.refcount == 0) {
        E.fail(out_error, .general, "refcount is already zero", @src());
        return false;
    }
    slot_ref.refcount -= 1;
    if (slot_ref.refcount > 0) return true;

    slot_ref.key = RC_TOMBSTONE;
    slot_ref.refcount = 0;
    s.resources.active -= 1;

    evictPathsForHandle(s, handle);

    if (s.destroy_fn) |d| d(handle, s.destroy_ctx);
    return true;
}

fn vtTryGetCached(self: ?*c.ke_resource_cache, key: [*c]const u8, out_handle: [*c]c.ke_resource_handle) callconv(.c) bool {
    if (self == null or key == null or out_handle == null) return false;
    const s = stateOf(self.?);
    var found = false;
    const idx = s.paths.probe(keyFromPath(key), &found);
    if (!found) return false;

    const h = s.paths.slots[idx].handle;
    if (!vtRetain(self, h, null)) {
        s.paths.slots[idx].key = RC_TOMBSTONE;
        s.paths.active -= 1;
        return false;
    }
    out_handle.* = h;
    return true;
}

fn vtCacheInsert(self: ?*c.ke_resource_cache, key: [*c]const u8, handle: c.ke_resource_handle, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    if (self == null or key == null or handle == HANDLE_NONE) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self.?);
    if (!s.paths.reserve()) {
        E.fail(out_error, .general, "path table rehash failed", @src());
        return false;
    }

    var found = false;
    const k = keyFromPath(key);
    const idx = s.paths.probe(k, &found);
    if (found) {
        E.fail(out_error, .already_exists, "key already in cache; call try_get_cached first", @src());
        return false;
    }

    if (s.paths.slots[idx].key == RC_EMPTY) s.paths.occupied += 1;
    s.paths.active += 1;
    s.paths.slots[idx] = .{ .key = k, .refcount = 0, .handle = handle };
    return true;
}

fn vtCacheEvict(self: ?*c.ke_resource_cache, key: [*c]const u8) callconv(.c) void {
    if (self == null or key == null) return;
    const s = stateOf(self.?);
    var found = false;
    const idx = s.paths.probe(keyFromPath(key), &found);
    if (!found) return;
    s.paths.slots[idx].key = RC_TOMBSTONE;
    s.paths.active -= 1;
}

fn vtDestroy(self: ?*c.ke_resource_cache) callconv(.c) void {
    const api = self orelse return;
    const s = stateOf(api);

    for (s.resources.slots) |*r| {
        if (r.key == RC_EMPTY or r.key == RC_TOMBSTONE) continue;
        const h = r.handle;
        r.key = RC_TOMBSTONE;
        if (s.destroy_fn) |d| d(h, s.destroy_ctx);
    }

    s.resources.deinit();
    s.paths.deinit();
    gpa.destroy(s);
}

export fn ke_resource_cache_create(params: [*c]const c.ke_resource_cache_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_resource_cache_handle {
    const empty = c.ke_resource_cache_handle{ .ref = null, .destroy = null };
    if (params == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return empty;
    }

    const s = gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return empty;
    };
    s.* = std.mem.zeroes(State);
    s.destroy_fn = params.*.destroy_fn;
    s.destroy_ctx = params.*.destroy_ctx;

    s.resources = Table.init(64) orelse {
        gpa.destroy(s);
        E.fail(out_error, .out_of_memory, "resources table allocation failed", @src());
        return empty;
    };
    s.paths = Table.init(64) orelse {
        s.resources.deinit();
        gpa.destroy(s);
        E.fail(out_error, .out_of_memory, "paths table allocation failed", @src());
        return empty;
    };

    s.api.handle = s;
    s.api.register_resource = &vtRegister;
    s.api.retain = &vtRetain;
    s.api.release = &vtRelease;
    s.api.try_get_cached = &vtTryGetCached;
    s.api.cache_insert = &vtCacheInsert;
    s.api.cache_evict = &vtCacheEvict;

    return .{ .ref = &s.api, .destroy = &vtDestroy };
}

const testing = std.testing;

var test_destroy_calls: i32 = 0;
var test_last_destroyed: c.ke_resource_handle = c.KE_RESOURCE_HANDLE_NONE;

fn countingDestroy(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    _ = ctx;
    test_destroy_calls += 1;
    test_last_destroyed = handle;
}

fn markerDestroy(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    _ = handle;
    const marker: *i32 = @ptrCast(@alignCast(ctx orelse return));
    marker.* += 1;
}

fn makeCountingCache() c.ke_resource_cache_handle {
    test_destroy_calls = 0;
    test_last_destroyed = c.KE_RESOURCE_HANDLE_NONE;
    var params = std.mem.zeroes(c.ke_resource_cache_params);
    params.destroy_fn = &countingDestroy;
    params.destroy_ctx = null;
    return ke_resource_cache_create(&params, null);
}

fn makeMarkerCache(marker: *i32) c.ke_resource_cache_handle {
    var params = std.mem.zeroes(c.ke_resource_cache_params);
    params.destroy_fn = &markerDestroy;
    params.destroy_ctx = marker;
    return ke_resource_cache_create(&params, null);
}

test "registering a resource starts its refcount at one" {
    const h = makeCountingCache();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 42, null));
    try testing.expect(h.ref.*.release.?(h.ref, 42, null));
    try testing.expect(!h.ref.*.release.?(h.ref, 42, null));
}

test "registering the none handle is rejected" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(!h.ref.*.register_resource.?(h.ref, c.KE_RESOURCE_HANDLE_NONE, null));
}

test "registering the same handle twice is rejected" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 7, null));
    try testing.expect(!h.ref.*.register_resource.?(h.ref, 7, null));
    try testing.expect(h.ref.*.release.?(h.ref, 7, null));
}

test "each retain adds a release the resource must wait for" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 1, null));
    try testing.expect(h.ref.*.retain.?(h.ref, 1, null));
    try testing.expect(h.ref.*.retain.?(h.ref, 1, null));
    try testing.expect(h.ref.*.release.?(h.ref, 1, null));
    try testing.expectEqual(@as(i32, 0), test_destroy_calls);
    try testing.expect(h.ref.*.release.?(h.ref, 1, null));
    try testing.expectEqual(@as(i32, 0), test_destroy_calls);
    try testing.expect(h.ref.*.release.?(h.ref, 1, null));
    try testing.expectEqual(@as(i32, 1), test_destroy_calls);
    try testing.expectEqual(@as(c.ke_resource_handle, 1), test_last_destroyed);
}

test "retaining an unknown handle fails" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(!h.ref.*.retain.?(h.ref, 999, null));
}

test "the destroy callback receives the context given at creation" {
    var marker: i32 = 0;
    const h = makeMarkerCache(&marker);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 100, null));
    try testing.expect(h.ref.*.release.?(h.ref, 100, null));
    try testing.expectEqual(@as(i32, 1), marker);
}

test "handle zero is an ordinary resource handle" {
    var marker: i32 = 0;
    const h = makeMarkerCache(&marker);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 0, null));
    try testing.expect(h.ref.*.retain.?(h.ref, 0, null));
    try testing.expect(h.ref.*.release.?(h.ref, 0, null));
    try testing.expectEqual(@as(i32, 0), marker);
    try testing.expect(h.ref.*.release.?(h.ref, 0, null));
    try testing.expectEqual(@as(i32, 1), marker);
}

test "looking up a path that was never cached misses" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    var out: c.ke_resource_handle = 0;
    try testing.expect(!h.ref.*.try_get_cached.?(h.ref, "res://missing", &out));
}

test "a cache hit returns the handle and retains it for the caller" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 10, null));
    try testing.expect(h.ref.*.cache_insert.?(h.ref, "res://x.mesh", 10, null));

    var out: c.ke_resource_handle = c.KE_RESOURCE_HANDLE_NONE;
    try testing.expect(h.ref.*.try_get_cached.?(h.ref, "res://x.mesh", &out));
    try testing.expectEqual(@as(c.ke_resource_handle, 10), out);
    try testing.expect(h.ref.*.release.?(h.ref, 10, null));
    try testing.expectEqual(@as(i32, 0), test_destroy_calls);
    try testing.expect(h.ref.*.release.?(h.ref, 10, null));
    try testing.expectEqual(@as(i32, 1), test_destroy_calls);
}

test "inserting a key that is already cached is rejected" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 20, null));
    try testing.expect(h.ref.*.register_resource.?(h.ref, 21, null));
    try testing.expect(h.ref.*.cache_insert.?(h.ref, "res://y.tex", 20, null));
    try testing.expect(!h.ref.*.cache_insert.?(h.ref, "res://y.tex", 21, null));
    try testing.expect(h.ref.*.release.?(h.ref, 20, null));
    try testing.expect(h.ref.*.release.?(h.ref, 21, null));
}

test "releasing the last reference evicts the cached path" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 20, null));
    try testing.expect(h.ref.*.cache_insert.?(h.ref, "res://y.tex", 20, null));
    try testing.expect(h.ref.*.release.?(h.ref, 20, null));

    var out: c.ke_resource_handle = 0;
    try testing.expect(!h.ref.*.try_get_cached.?(h.ref, "res://y.tex", &out));
}

test "evicting a path leaves the resource itself alive" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 30, null));
    try testing.expect(h.ref.*.cache_insert.?(h.ref, "res://z.mat", 30, null));

    h.ref.*.cache_evict.?(h.ref, "res://z.mat");
    var out: c.ke_resource_handle = 0;
    try testing.expect(!h.ref.*.try_get_cached.?(h.ref, "res://z.mat", &out));
    try testing.expectEqual(@as(i32, 0), test_destroy_calls);
    try testing.expect(h.ref.*.release.?(h.ref, 30, null));
    try testing.expectEqual(@as(i32, 1), test_destroy_calls);
}

test "every resource survives the rehashes caused by many insertions" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    const n: c.ke_resource_handle = 200;
    var i: c.ke_resource_handle = 1;
    while (i <= n) : (i += 1) {
        try testing.expect(h.ref.*.register_resource.?(h.ref, i, null));
    }
    i = 1;
    while (i <= n) : (i += 1) {
        try testing.expect(h.ref.*.retain.?(h.ref, i, null));
        try testing.expect(h.ref.*.release.?(h.ref, i, null));
    }
    i = 1;
    while (i <= n) : (i += 1) {
        try testing.expect(h.ref.*.release.?(h.ref, i, null));
    }
    try testing.expectEqual(@as(i32, 200), test_destroy_calls);
}

test "a handle registered into a tombstoned slot behaves like any other" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 1, null));
    try testing.expect(h.ref.*.release.?(h.ref, 1, null));
    try testing.expect(h.ref.*.register_resource.?(h.ref, 65, null));
    try testing.expect(h.ref.*.retain.?(h.ref, 65, null));
    try testing.expect(h.ref.*.release.?(h.ref, 65, null));
    try testing.expect(h.ref.*.release.?(h.ref, 65, null));
    try testing.expect(!h.ref.*.retain.?(h.ref, 65, null));
}

test "a cached path pointing at an unregistered handle reports a miss" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.cache_insert.?(h.ref, "res://stale", 500, null));
    var out: c.ke_resource_handle = 0;
    try testing.expect(!h.ref.*.try_get_cached.?(h.ref, "res://stale", &out));
}

test "inserting with a null cache, a null key or the none handle is rejected" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(!h.ref.*.cache_insert.?(null, null, 0, null));
    try testing.expect(!h.ref.*.cache_insert.?(h.ref, null, 0, null));
    try testing.expect(!h.ref.*.cache_insert.?(h.ref, "x", c.KE_RESOURCE_HANDLE_NONE, null));
}

test "evicting with a null cache or a null key is a no-op" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    h.ref.*.cache_evict.?(null, null);
    h.ref.*.cache_evict.?(h.ref, null);
}

test "a released slot is reused without losing later lookups" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 1, null));
    try testing.expect(h.ref.*.register_resource.?(h.ref, 2, null));
    try testing.expect(h.ref.*.release.?(h.ref, 1, null));
    try testing.expect(h.ref.*.register_resource.?(h.ref, 3, null));

    var out: c.ke_resource_handle = 0;
    try testing.expect(h.ref.*.cache_insert.?(h.ref, "res://3", 3, null));
    try testing.expect(h.ref.*.try_get_cached.?(h.ref, "res://3", &out));
    try testing.expectEqual(@as(c.ke_resource_handle, 3), out);
}

test "a rehash triggered while tombstones are present keeps the table consistent" {
    const h = makeCountingCache();
    defer h.destroy.?(h.ref);

    var i: c.ke_resource_handle = 1;
    while (i <= 40) : (i += 1) {
        try testing.expect(h.ref.*.register_resource.?(h.ref, i, null));
    }
    i = 1;
    while (i <= 20) : (i += 1) {
        try testing.expect(h.ref.*.release.?(h.ref, i, null));
    }
    i = 41;
    while (i <= 100) : (i += 1) {
        try testing.expect(h.ref.*.register_resource.?(h.ref, i, null));
    }

    var out: c.ke_resource_handle = 0;
    try testing.expect(!h.ref.*.try_get_cached.?(h.ref, "res://missing", &out));

    i = 21;
    while (i <= 100) : (i += 1) {
        try testing.expect(h.ref.*.retain.?(h.ref, i, null));
        try testing.expect(h.ref.*.release.?(h.ref, i, null));
    }
}

test "destroying the cache runs the destroy callback for every live resource" {
    var marker: i32 = 0;
    const h = makeMarkerCache(&marker);

    try testing.expect(h.ref.*.register_resource.?(h.ref, 5, null));
    try testing.expect(h.ref.*.register_resource.?(h.ref, 6, null));
    try testing.expect(h.ref.*.retain.?(h.ref, 6, null));

    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i32, 2), marker);
}

test "creating, using and destroying a resource cache leaves no block allocated" {
    const h = makeCountingCache();
    try testing.expect(h.ref.*.register_resource.?(h.ref, 42, null));
    try testing.expect(h.ref.*.release.?(h.ref, 42, null));
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

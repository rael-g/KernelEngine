const std = @import("std");

const gpa = std.heap.c_allocator;

const c = @cImport({
    @cInclude("kernel_engine/resource_cache/resource_cache.h");
});

// Zig-native error translation at the C-ABI seam (no ke_common link).
const E = @import("kerror").Errors(c);

// Open-addressed table with tombstones for both the handle→entry and
// path→handle directions. destroy_fn is per-cache (set at construction); all
// resources in a cache share the same destructor.

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
    key: u64 = 0, // 0 = empty, maxU64 = tombstone
    refcount: u32 = 0, // resource entries only
    handle: u32 = 0, // resource: redundant; path: target handle
};

const Table = struct {
    slots: []Slot,
    capacity: usize, // power of two
    occupied: usize, // active + tombstones
    active: usize, // active only

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

    // Finds the slot for `key`. Returns the matching active entry, or the first
    // usable slot (preferring tombstones over empty so reinsertion keeps probe
    // chains short). `found` discriminates.
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
    return @as(u64, h) + 1; // +1 keeps 0 reserved for EMPTY
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

// ── vtable: lifetime ────────────────────────────────────────────────────────

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

// Walks the path table and tombstones any entry pointing at `handle`.
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

// ── vtable: path cache ──────────────────────────────────────────────────────

fn vtTryGetCached(self: ?*c.ke_resource_cache, key: [*c]const u8, out_handle: [*c]c.ke_resource_handle) callconv(.c) bool {
    if (self == null or key == null or out_handle == null) return false;
    const s = stateOf(self.?);
    var found = false;
    const idx = s.paths.probe(keyFromPath(key), &found);
    if (!found) return false;

    const h = s.paths.slots[idx].handle;
    // Retain on behalf of caller. If the underlying resource vanished (stale
    // path entry), drop the path entry and report cache miss.
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

// ── vtable: teardown ────────────────────────────────────────────────────────

fn vtDestroy(self: ?*c.ke_resource_cache) callconv(.c) void {
    const api = self orelse return;
    const s = stateOf(api);

    // Fire destroy callback for every resource still alive.
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

// ── Factory ─────────────────────────────────────────────────────────────────

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

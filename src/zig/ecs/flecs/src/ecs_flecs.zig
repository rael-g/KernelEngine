
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

const flecs_fatal_type: c.ke_error_type = .{ .name = "ke.ecs.flecs.fatal", .parent = null };

threadlocal var last_msg_buf: [1024]u8 = undefined;
threadlocal var last_msg_len: usize = 0;

fn flecsLogHandler(level: i32, file: [*c]const u8, line: i32, msg: [*c]const u8) callconv(.c) void {
    if (level >= 0 or msg == null) return;
    const f: []const u8 = if (file != null) std.mem.span(file) else "?";
    const m: []const u8 = std.mem.span(msg);
    const dst = last_msg_buf[0 .. last_msg_buf.len - 1];
    const written = std.fmt.bufPrint(dst, "{s}:{d}: {s}", .{ f, line, m }) catch dst[0..0];
    last_msg_len = written.len;
}

fn flecsAbortHandler() callconv(.c) void {
    last_msg_buf[last_msg_len] = 0;
    const msg: [*:0]const u8 = if (last_msg_len > 0) @ptrCast(&last_msg_buf) else "flecs fatal (no message captured)";
    const err = c.ke_error{
        .type = &flecs_fatal_type,
        .message = msg,
        .file = null,
        .line = 0,
        .cause = null,
    };
    E.fatal(&err);
}

var os_api_installed: bool = false;

fn installFlecsOsApi() void {
    if (os_api_installed) return;
    c.ecs_os_set_api_defaults();
    var api = c.ecs_os_get_api();
    api.log_ = flecsLogHandler;
    api.abort_ = flecsAbortHandler;
    c.ecs_os_set_api(&api);
    os_api_installed = true;
}

const QueryCacheEntry = struct {
    cid: c.ke_component_id,
    query: ?*c.ecs_query_t,
};

/// A multi-term query registered via query_register — the parallel-safe read path.
/// query_resolve walks it single-threaded into ke_ecs_segment lists; the wave
/// bodies then read those segments as plain memory (no flecs call).
const RegisteredQuery = struct {
    query: ?*c.ecs_query_t,
    elem_sizes: [c.KE_QUERY_MAX_TERMS]usize,
    term_count: usize,
};

/// First id flecs' own allocator may issue. Everything between the ids the world
/// is born with and this mark is the pool entity_reserve draws from. The world's
/// side is unbounded; only the reserve pool is sized, which is why the split
/// doubles as its capacity and is overridable through the params.
const default_world_id_base: u32 = 1 << 20;

const State = struct {
    api: c.ke_ecs,
    world: ?*c.ecs_world_t,

    reserve_low: u32,
    reserve_end: u32,
    reserve_next: std.atomic.Value(u32),
    /// One bit per pool slot, recording that the id has already been given its
    /// one life. flecs cannot answer this: deleting an id outside its active
    /// range removes every trace of it, so asking the world whether an id ever
    /// existed reports the same "no" for one never used and one destroyed.
    materialized: ?[]u8,

    queries: ?[*]QueryCacheEntry,
    query_count: usize,
    query_capacity: usize,

    rqueries: ?[*]RegisteredQuery,
    rquery_count: usize,
    rquery_capacity: usize,
};

fn stateOf(self: *c.ke_ecs) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn findOrCreateQuery(s: *State, cid: c.ke_component_id) ?*QueryCacheEntry {
    if (s.queries) |qs| {
        for (0..s.query_count) |i| {
            if (qs[i].cid == cid) return &qs[i];
        }
    }

    if (s.query_count == s.query_capacity) {
        const new_cap: usize = if (s.query_capacity != 0) s.query_capacity * 2 else 8;
        const new_buf = heap.gpa.alloc(QueryCacheEntry, new_cap) catch return null;
        if (s.queries) |old| {
            @memcpy(new_buf[0..s.query_count], old[0..s.query_count]);
            heap.gpa.free(old[0..s.query_capacity]);
        }
        s.queries = new_buf.ptr;
        s.query_capacity = new_cap;
    }

    var desc: c.ecs_query_desc_t = std.mem.zeroes(c.ecs_query_desc_t);
    desc.terms[0].id = @intCast(cid);
    const q = c.ecs_query_init(s.world, &desc) orelse return null;

    const entry = &s.queries.?[s.query_count];
    s.query_count += 1;
    entry.* = .{ .cid = cid, .query = q };
    return entry;
}

fn entityCreate(self_in: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    const s = stateOf(self);
    return @intCast(c.ecs_new(s.world));
}

/// Hands out an id without touching the world, which is the whole point: this is
/// the one entity operation a system body may call from a parallel wave, and
/// flecs' own id allocator walks a shared entity index that corrupts under
/// concurrent use. The id comes from a band flecs is configured never to issue
/// from, so the two allocators cannot meet, and the world learns about it later —
/// see `materializeReserved`. Returns 0 once the pool is spent.
fn entityReserve(self_in: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    const s = stateOf(self);
    const offset = s.reserve_next.fetchAdd(1, .monotonic);
    if (offset >= s.reserve_end - s.reserve_low) return 0;
    return @as(c.ke_entity, s.reserve_low) + offset;
}

/// Brings a reserved id into the world the first time anything is attached to it.
///
/// Only reachable single-threaded: the runtime flushes its defer queue after the
/// wave barrier, so this runs where a world mutation is safe. An id outside the
/// pool was issued by flecs and is already as alive as it will ever be.
fn entityMaterialize(self_in: ?*c.ke_ecs, entity: c.ke_entity) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or entity == 0) return;
    materializeReserved(stateOf(self), entity);
}

fn materializeReserved(s: *State, entity: c.ke_entity) void {
    if (entity < s.reserve_low or entity >= s.reserve_end) return;

    const bits = s.materialized orelse blk: {
        const bytes = ((s.reserve_end - s.reserve_low) + 7) / 8;
        const buf = heap.gpa.alloc(u8, bytes) catch return;
        @memset(buf, 0);
        s.materialized = buf;
        break :blk buf;
    };

    const slot: u32 = @intCast(entity - s.reserve_low);
    const mask = @as(u8, 1) << @intCast(slot % 8);
    if (bits[slot / 8] & mask != 0) return;
    bits[slot / 8] |= mask;
    c.ecs_make_alive(s.world, @intCast(entity));
}

fn entityDestroy(self_in: ?*c.ke_ecs, entity: c.ke_entity) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or entity == 0) return;
    const s = stateOf(self);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return;
    c.ecs_delete(s.world, @intCast(entity));
}

fn componentRegister(
    self_in: ?*c.ke_ecs,
    name: [*c]const u8,
    size: usize,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_component_id {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return 0;
    };
    if (self.handle == null or name == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return 0;
    }
    const s = stateOf(self);

    const existing = c.ecs_lookup(s.world, name);
    if (existing != 0) {
        const ti = c.ecs_get_type_info(s.world, @intCast(existing));
        const existing_size: usize = if (ti != null) @intCast(ti.*.size) else 0;
        if (existing_size != size) {
            E.fail(out_error, .invalid_argument, "component already registered with a different size", @src());
            return 0;
        }
        _ = findOrCreateQuery(s, @truncate(existing));
        return @truncate(existing);
    }

    var edesc: c.ecs_entity_desc_t = std.mem.zeroes(c.ecs_entity_desc_t);
    edesc.name = name;
    const e = c.ecs_entity_init(s.world, &edesc);

    if (size == 0) {
        _ = findOrCreateQuery(s, @truncate(e));
        return @truncate(e);
    }

    var cdesc: c.ecs_component_desc_t = std.mem.zeroes(c.ecs_component_desc_t);
    cdesc.entity = e;
    cdesc.type.size = @intCast(size);
    cdesc.type.alignment = @intCast(@alignOf(c.max_align_t));
    const cid: c.ke_component_id = @truncate(c.ecs_component_init(s.world, &cdesc));

    _ = findOrCreateQuery(s, cid);
    return cid;
}

fn componentLookup(
    self_in: ?*c.ke_ecs,
    name: [*c]const u8,
    out_meta: [*c]c.ke_component_meta,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or name == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self);

    const e = c.ecs_lookup(s.world, name);
    if (e == 0) {
        E.fail(out_error, .not_found, "component not found", @src());
        return false;
    }

    const ti = c.ecs_get_type_info(s.world, @intCast(e));
    if (ti == null) {
        E.fail(out_error, .not_found, "component type info not found", @src());
        return false;
    }

    if (out_meta != null) {
        out_meta.*.cid = @truncate(e);
        out_meta.*.size = @intCast(ti.*.size);
        out_meta.*.fields = null;
        out_meta.*.field_count = 0;
    }
    return true;
}

fn componentAdd(self_in: ?*c.ke_ecs, entity: c.ke_entity, component: c.ke_component_id) callconv(.c) ?*anyopaque {
    const self = self_in orelse return null;
    if (self.handle == null or entity == 0 or component == 0) return null;
    const s = stateOf(self);
    materializeReserved(s, entity);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return null;

    c.ecs_add_id(s.world, @intCast(entity), @intCast(component));
    const ti = c.ecs_get_type_info(s.world, @intCast(component));
    return if (ti != null and ti.*.size > 0)
        c.ecs_get_mut_id(s.world, @intCast(entity), @intCast(component))
    else
        null;
}

fn componentRemove(self_in: ?*c.ke_ecs, entity: c.ke_entity, component: c.ke_component_id) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or entity == 0 or component == 0) return;
    const s = stateOf(self);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return;
    c.ecs_remove_id(s.world, @intCast(entity), @intCast(component));
}

fn componentGet(self_in: ?*c.ke_ecs, entity: c.ke_entity, component: c.ke_component_id) callconv(.c) ?*anyopaque {
    const self = self_in orelse return null;
    if (self.handle == null or entity == 0 or component == 0) return null;
    const s = stateOf(self);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return null;
    if (!c.ecs_has_id(s.world, @intCast(entity), @intCast(component))) return null;
    return @constCast(c.ecs_get_id(s.world, @intCast(entity), @intCast(component)));
}

fn componentSize(self_in: ?*c.ke_ecs, cid: c.ke_component_id) callconv(.c) usize {
    const self = self_in orelse return 0;
    if (self.handle == null or cid == 0) return 0;
    const s = stateOf(self);
    const ti = c.ecs_get_type_info(s.world, @intCast(cid));
    if (ti == null) return 0;
    return @intCast(ti.*.size);
}

fn queryRegister(self_in: ?*c.ke_ecs, cids: [*c]const c.ke_component_id, cid_count: usize) callconv(.c) c.ke_query_id {
    const self = self_in orelse return c.KE_QUERY_INVALID;
    if (self.handle == null or cids == null or cid_count == 0 or cid_count > c.KE_QUERY_MAX_TERMS)
        return c.KE_QUERY_INVALID;
    const s = stateOf(self);

    var desc: c.ecs_query_desc_t = std.mem.zeroes(c.ecs_query_desc_t);
    for (0..cid_count) |i| desc.terms[i].id = @intCast(cids[i]);
    const q = c.ecs_query_init(s.world, &desc) orelse return c.KE_QUERY_INVALID;

    if (s.rquery_count == s.rquery_capacity) {
        const new_cap: usize = if (s.rquery_capacity != 0) s.rquery_capacity * 2 else 8;
        const new_buf = heap.gpa.alloc(RegisteredQuery, new_cap) catch {
            c.ecs_query_fini(q);
            return c.KE_QUERY_INVALID;
        };
        if (s.rqueries) |old| {
            @memcpy(new_buf[0..s.rquery_count], old[0..s.rquery_count]);
            heap.gpa.free(old[0..s.rquery_capacity]);
        }
        s.rqueries = new_buf.ptr;
        s.rquery_capacity = new_cap;
    }

    const rq = &s.rqueries.?[s.rquery_count];
    rq.query = q;
    rq.term_count = cid_count;
    for (0..cid_count) |i| {
        const ti = c.ecs_get_type_info(s.world, @intCast(cids[i]));
        rq.elem_sizes[i] = if (ti != null) @intCast(ti.*.size) else 0;
    }
    const id: c.ke_query_id = @intCast(s.rquery_count + 1);
    s.rquery_count += 1;
    return id;
}

fn queryResolve(
    self_in: ?*c.ke_ecs,
    query: c.ke_query_id,
    out_segments: [*c]c.ke_ecs_segment,
    max_segments: usize,
    out_count: [*c]usize,
) callconv(.c) void {
    if (out_count != null) out_count.* = 0;
    const self = self_in orelse return;
    if (self.handle == null or query == c.KE_QUERY_INVALID or out_segments == null or max_segments == 0) return;
    const s = stateOf(self);
    const idx: usize = @intCast(query - 1);
    if (idx >= s.rquery_count) return;
    const rq = &s.rqueries.?[idx];
    const q = rq.query orelse return;

    var seg: usize = 0;
    var it = c.ecs_query_iter(s.world, q);
    while (c.ecs_query_next(&it)) {
        if (seg >= max_segments) {
            c.ecs_iter_fini(&it);
            break;
        }
        const dst = &out_segments[seg];
        dst.entities = @ptrCast(it.entities);
        dst.count = @intCast(it.count);
        for (0..rq.term_count) |t|
            dst.columns[t] = if (rq.elem_sizes[t] != 0) c.ecs_field_w_size(&it, rq.elem_sizes[t], @intCast(t)) else null;
        for (rq.term_count..c.KE_QUERY_MAX_TERMS) |t| dst.columns[t] = null;
        seg += 1;
    }
    if (out_count != null) out_count.* = seg;
}

fn destroy(self_in: ?*c.ke_ecs) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);

    if (s.queries) |qs| {
        for (0..s.query_count) |i| {
            if (qs[i].query) |q| c.ecs_query_fini(q);
        }
        heap.gpa.free(qs[0..s.query_capacity]);
    }
    if (s.rqueries) |rqs| {
        for (0..s.rquery_count) |i| {
            if (rqs[i].query) |q| c.ecs_query_fini(q);
        }
        heap.gpa.free(rqs[0..s.rquery_capacity]);
    }
    if (s.materialized) |m| heap.gpa.free(m);
    if (s.world) |w| _ = c.ecs_fini(w);

    heap.gpa.destroy(s);
}

export fn ke_ecs_flecs_create(
    params_in: ?*const c.ke_ecs_flecs_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_ecs_handle {
    const null_handle = std.mem.zeroes(c.ke_ecs_handle);

    const world_id_base: u32 = blk: {
        const p = params_in orelse break :blk default_world_id_base;
        break :blk if (p.*.world_id_base == 0) default_world_id_base else p.*.world_id_base;
    };

    installFlecsOsApi();

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = .{
        .api = std.mem.zeroes(c.ke_ecs),
        .world = null,
        .reserve_low = 0,
        .reserve_end = world_id_base,
        .reserve_next = std.atomic.Value(u32).init(0),
        .materialized = null,
        .queries = null,
        .query_count = 0,
        .query_capacity = 0,
        .rqueries = null,
        .rquery_count = 0,
        .rquery_capacity = 0,
    };

    s.world = c.ecs_init();
    if (s.world == null) {
        heap.gpa.destroy(s);
        E.fail(out_error, .not_initialized, "flecs world init failed", @src());
        return null_handle;
    }

    s.reserve_low = @intCast(c.ecs_get_max_id(s.world) + 1);
    if (world_id_base <= s.reserve_low) {
        _ = c.ecs_fini(s.world);
        heap.gpa.destroy(s);
        E.fail(out_error, .invalid_argument, "world_id_base must leave room below it for the reserve pool", @src());
        return null_handle;
    }
    if (c.ecs_entity_range_new(s.world, world_id_base, 0)) |range| {
        c.ecs_entity_range_set(s.world, range);
    } else {
        _ = c.ecs_fini(s.world);
        heap.gpa.destroy(s);
        E.fail(out_error, .not_initialized, "flecs would not keep its ids clear of the reserve pool", @src());
        return null_handle;
    }

    s.api.handle = s;
    s.api.entity_create = entityCreate;
    s.api.entity_reserve = entityReserve;
    s.api.entity_materialize = entityMaterialize;
    s.api.entity_destroy = entityDestroy;
    s.api.component_register = componentRegister;
    s.api.component_lookup = componentLookup;
    s.api.component_add = componentAdd;
    s.api.component_remove = componentRemove;
    s.api.component_get = componentGet;
    s.api.component_size = componentSize;
    s.api.query_register = queryRegister;
    s.api.query_resolve = queryResolve;

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;

test "flecsLogHandler stashes a fatal-level message with file:line" {
    last_msg_len = 0;
    flecsLogHandler(-4, "flecs_internal.c", 42, "assertion failed: foo");
    try testing.expect(last_msg_len > 0);
    try testing.expectEqualStrings(
        "flecs_internal.c:42: assertion failed: foo",
        last_msg_buf[0..last_msg_len],
    );
}

test "flecsLogHandler ignores non-fatal levels" {
    last_msg_len = 0;
    flecsLogHandler(1, "flecs_internal.c", 1, "just some info");
    try testing.expectEqual(@as(usize, 0), last_msg_len);
}

test "flecsLogHandler ignores a null message" {
    last_msg_len = 0;
    flecsLogHandler(-1, "flecs_internal.c", 1, null);
    try testing.expectEqual(@as(usize, 0), last_msg_len);
}

test "componentRegister rejects re-registering a name with a different size" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);

    var out_error: ?*c.ke_error = null;
    const first = handle.ref.*.component_register.?(handle.ref, "dup_name", 8, &out_error);
    try testing.expect(first != 0);
    try testing.expect(out_error == null);

    const second = handle.ref.*.component_register.?(handle.ref, "dup_name", 16, &out_error);
    try testing.expectEqual(@as(c.ke_component_id, 0), second);
    try testing.expect(out_error != null);
}

test "componentRegister is idempotent for a repeated identical size" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);

    var out_error: ?*c.ke_error = null;
    const first = handle.ref.*.component_register.?(handle.ref, "same_name", 12, &out_error);
    const second = handle.ref.*.component_register.?(handle.ref, "same_name", 12, &out_error);
    try testing.expectEqual(first, second);
    try testing.expect(out_error == null);
}

/// Test-only entry point for abort_probe.zig. Installs the real os_api hooks
/// (the same call ke_ecs_flecs_create makes) and forces the exact assertion
/// componentAdd exists to prevent — asking flecs directly for the mutable
/// storage of a zero-size tag — proving the whole chain (real internal
/// assertion -> installed hooks -> E.fatal -> process exit) without exposing
/// anything through the public C surface, which has no path left to reach a
/// flecs assert once the wrapper's own guards are in the way. Never returns.
pub fn debugTriggerRealFlecsAssertion() void {
    installFlecsOsApi();

    const world = c.ecs_init();
    var edesc: c.ecs_entity_desc_t = std.mem.zeroes(c.ecs_entity_desc_t);
    edesc.name = "ProbeTag";
    const tag = c.ecs_entity_init(world, &edesc);
    const e = c.ecs_new(world);
    c.ecs_add_id(world, e, tag);

    _ = c.ecs_get_mut_id(world, e, tag);
}

test "a reserved id can never be one the world's own allocator will issue" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const reserved = e.entity_reserve.?(handle.ref);
    try testing.expect(reserved != 0);
    try testing.expect(reserved < default_world_id_base);

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const created = e.entity_create.?(handle.ref);
        try testing.expect(created >= default_world_id_base);
    }
}

test "reserving past the pool's capacity reports exhaustion instead of colliding" {
    var params = c.ke_ecs_flecs_params{ .world_id_base = 0 };
    const probe = ke_ecs_flecs_create(&params, null);
    const low = stateOf(probe.ref.?).reserve_low;
    probe.destroy.?(probe.ref);

    params.world_id_base = low + 4;
    const handle = ke_ecs_flecs_create(&params, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    var i: usize = 0;
    while (i < 4) : (i += 1) try testing.expect(e.entity_reserve.?(handle.ref) != 0);
    try testing.expectEqual(@as(c.ke_entity, 0), e.entity_reserve.?(handle.ref));
}

test "every reserved id is distinct" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    var seen: [256]c.ke_entity = undefined;
    for (&seen) |*slot| slot.* = e.entity_reserve.?(handle.ref);
    for (seen, 0..) |a, i| {
        try testing.expect(a != 0);
        for (seen[i + 1 ..]) |b| try testing.expect(a != b);
    }
}

test "reserving concurrently never hands the same id to two threads" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);

    const thread_count = 8;
    const per_thread = 2000;
    var ids: [thread_count][per_thread]c.ke_entity = undefined;

    const Worker = struct {
        fn run(ecs: *c.ke_ecs, out: *[per_thread]c.ke_entity) void {
            for (out) |*slot| slot.* = ecs.entity_reserve.?(ecs);
        }
    };

    var threads: [thread_count]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, Worker.run, .{ handle.ref.?, &ids[i] });
    }
    for (threads) |t| t.join();

    var flat: [thread_count * per_thread]c.ke_entity = undefined;
    for (ids, 0..) |row, i| @memcpy(flat[i * per_thread ..][0..per_thread], &row);
    std.mem.sort(c.ke_entity, &flat, {}, std.sort.asc(c.ke_entity));
    for (flat[1..], 0..) |v, i| {
        try testing.expect(v != 0);
        try testing.expect(v != flat[i]);
    }
}

test "a reserved id is not in the world until something materializes it" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const cid = e.component_register.?(handle.ref, "reserve_probe", 4, null);
    const reserved = e.entity_reserve.?(handle.ref);
    try testing.expect(e.component_get.?(handle.ref, reserved, cid) == null);

    e.entity_materialize.?(handle.ref, reserved);
    try testing.expect(e.component_add.?(handle.ref, reserved, cid) != null);
}

test "attaching to a reserved id materializes it without a separate call" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const cid = e.component_register.?(handle.ref, "attach_probe", 4, null);
    const reserved = e.entity_reserve.?(handle.ref);

    const slot = e.component_add.?(handle.ref, reserved, cid) orelse return error.TestUnexpectedResult;
    @as(*u32, @ptrCast(@alignCast(slot))).* = 0xabcd;
    const read = e.component_get.?(handle.ref, reserved, cid) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 0xabcd), @as(*u32, @ptrCast(@alignCast(read))).*);
}

test "materializing an id twice is a no-op rather than a second entity" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const cid = e.component_register.?(handle.ref, "twice_probe", 4, null);
    const reserved = e.entity_reserve.?(handle.ref);
    e.entity_materialize.?(handle.ref, reserved);
    const slot = e.component_add.?(handle.ref, reserved, cid) orelse return error.TestUnexpectedResult;
    @as(*u32, @ptrCast(@alignCast(slot))).* = 7;

    e.entity_materialize.?(handle.ref, reserved);
    const read = e.component_get.?(handle.ref, reserved, cid) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 7), @as(*u32, @ptrCast(@alignCast(read))).*);
}

test "materializing an id the world already owns leaves it alone" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const cid = e.component_register.?(handle.ref, "owned_probe", 4, null);
    const created = e.entity_create.?(handle.ref);
    const slot = e.component_add.?(handle.ref, created, cid) orelse return error.TestUnexpectedResult;
    @as(*u32, @ptrCast(@alignCast(slot))).* = 99;

    e.entity_materialize.?(handle.ref, created);
    const read = e.component_get.?(handle.ref, created, cid) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 99), @as(*u32, @ptrCast(@alignCast(read))).*);
}

test "a split that leaves no room for the reserve pool is refused" {
    var params = c.ke_ecs_flecs_params{ .world_id_base = 1 };
    var out_error: ?*c.ke_error = null;
    const handle = ke_ecs_flecs_create(&params, &out_error);
    try testing.expect(handle.ref == null);
    try testing.expect(out_error != null);
}

test "a caller may move the split between the two id allocators" {
    var params = c.ke_ecs_flecs_params{ .world_id_base = 1_000_000 };
    const handle = ke_ecs_flecs_create(&params, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    try testing.expect(e.entity_reserve.?(handle.ref) < 1_000_000);
    try testing.expect(e.entity_create.?(handle.ref) >= 1_000_000);
}

test "a reserved entity that was destroyed does not come back on the next attach" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const cid = e.component_register.?(handle.ref, "revive_probe", 4, null);
    const reserved = e.entity_reserve.?(handle.ref);
    try testing.expect(e.component_add.?(handle.ref, reserved, cid) != null);

    e.entity_destroy.?(handle.ref, reserved);
    try testing.expect(e.component_add.?(handle.ref, reserved, cid) == null);
    try testing.expect(e.component_get.?(handle.ref, reserved, cid) == null);
}

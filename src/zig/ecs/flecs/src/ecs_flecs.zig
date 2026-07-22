// ke_ecs_flecs — flecs-backed implementation of the ke_ecs contract.
//
// Storage-only flecs wrapper. Implements the ke_ecs vtable by delegating to
// flecs's archetype storage + query engine. The scheduler is OUR ke_runtime;
// flecs's pipeline/system/timer addons are not referenced.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

// ── Abort interception ───────────────────────────────────────────────────────
//
// flecs calls ecs_os_api.abort_() on an internal assertion failure. We replace
// that slot (and log_, to capture the message that precedes it) so the
// process ends through E.fatal() — a readable message on stderr, no OS crash
// dialog — instead of libc's abort(). flecs offers no way to recover a world
// past an internal assertion, so this is a clean give-up, not a caught
// exception: nothing calls back into this world afterward. ecs_os_api is
// process-global; installed once, guarded by os_api_installed.

const flecs_fatal_type: c.ke_error_type = .{ .name = "ke.ecs.flecs.fatal", .parent = null };

// flecs logs the assertion detail (file/line/message) immediately before
// calling abort_(), on the same thread — so the abort handler picks it up
// from here rather than getting a bare "assertion failed".
threadlocal var last_msg_buf: [1024]u8 = undefined;
threadlocal var last_msg_len: usize = 0;

fn flecsLogHandler(level: i32, file: [*c]const u8, line: i32, msg: [*c]const u8) callconv(.c) void {
    // flecs uses negative levels for fatal/error messages.
    if (level >= 0 or msg == null) return;
    const f: []const u8 = if (file != null) std.mem.span(file) else "?";
    const m: []const u8 = std.mem.span(msg);
    const dst = last_msg_buf[0 .. last_msg_buf.len - 1]; // headroom for the NUL fatal() needs
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

// flecs's own ecs_os_set_api only takes effect on the first call per process
// (verified empirically: a second override is silently ignored), so these
// hooks can only ever be installed once — hence the guard, not just an
// optimization.
fn installFlecsOsApi() void {
    if (os_api_installed) return;
    // Populate defaults first so we only override the two slots we care about
    // and don't accidentally zero-out malloc/free/threading pointers.
    c.ecs_os_set_api_defaults();
    var api = c.ecs_os_get_api();
    api.log_ = flecsLogHandler;
    api.abort_ = flecsAbortHandler;
    c.ecs_os_set_api(&api);
    os_api_installed = true;
}

// ── State ────────────────────────────────────────────────────────────────────

const QueryCacheEntry = struct {
    cid: c.ke_component_id,
    query: ?*c.ecs_query_t,
};

/// A multi-term query registered via query_register — the parallel-safe read path.
/// query_resolve walks it single-threaded into ke_ecs_segment lists; the wave
/// bodies then read those segments as plain memory (no flecs call).
const RegisteredQuery = struct {
    query: ?*c.ecs_query_t,
    elem_sizes: [c.KE_QUERY_MAX_TERMS]usize, // 0 for a tag term (no column)
    term_count: usize,
};

const State = struct {
    api: c.ke_ecs,
    world: ?*c.ecs_world_t,

    // Query cache — populated eagerly at component_register (so no query is
    // ever created mid-tick, only at startup registration, single-threaded).
    queries: ?[*]QueryCacheEntry,
    query_count: usize,
    query_capacity: usize,

    // Multi-term registered queries (the parallel-safe path; see RegisteredQuery).
    rqueries: ?[*]RegisteredQuery,
    rquery_count: usize,
    rquery_capacity: usize,
};

fn stateOf(self: *c.ke_ecs) *State {
    return @ptrCast(@alignCast(self.handle));
}

// ── Helpers ──────────────────────────────────────────────────────────────────

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

// ── Vtable impls ─────────────────────────────────────────────────────────────

fn entityCreate(self_in: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    const s = stateOf(self);
    // ecs_new returns an empty entity, ignoring any ambient scope/with state —
    // this wrapper hands out bare ids and lets the caller add components.
    return @intCast(c.ecs_new(s.world));
}

fn entityReserve(self_in: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    const s = stateOf(self);
    // ecs_new is the atomic id allocator: safe to call while the world is in
    // readonly mode (a parallel wave) from any thread. It returns an empty,
    // alive entity — component storage is added later through the defer queue.
    return @intCast(c.ecs_new(s.world));
}

fn entityDestroy(self_in: ?*c.ke_ecs, entity: c.ke_entity) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or entity == 0) return;
    const s = stateOf(self);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return;
    c.ecs_delete(s.world, @intCast(entity));
}

fn componentRegister(self_in: ?*c.ke_ecs, name: [*c]const u8, size: usize) callconv(.c) c.ke_component_id {
    const self = self_in orelse return 0;
    if (self.handle == null or name == null) return 0;
    const s = stateOf(self);

    // Reuse if already registered with the same name (idempotent for module reloads).
    const existing = c.ecs_lookup(s.world, name);
    if (existing != 0) {
        _ = findOrCreateQuery(s, @truncate(existing));
        return @truncate(existing);
    }

    var edesc: c.ecs_entity_desc_t = std.mem.zeroes(c.ecs_entity_desc_t);
    edesc.name = name;
    const e = c.ecs_entity_init(s.world, &edesc);

    // A zero-size component is a tag (entity id, no data). flecs asserts if asked
    // to init a component with size 0, so register it as a pure tag — valid in
    // add/has/query and as a dependency key (render-resource cids are tags).
    if (size == 0) {
        // Warm the query now: creating a query is forbidden once the world enters
        // readonly mode during a parallel wave, so all queries must exist upfront.
        _ = findOrCreateQuery(s, @truncate(e));
        return @truncate(e);
    }

    var cdesc: c.ecs_component_desc_t = std.mem.zeroes(c.ecs_component_desc_t);
    cdesc.entity = e;
    cdesc.type.size = @intCast(size);
    cdesc.type.alignment = @intCast(@alignOf(c.max_align_t));
    const cid: c.ke_component_id = @truncate(c.ecs_component_init(s.world, &cdesc));

    _ = findOrCreateQuery(s, cid); // warm before any readonly wave (see above)
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
        out_meta.*.fields = null; // field reflection not used through this impl
        out_meta.*.field_count = 0;
    }
    return true;
}

fn componentAdd(self_in: ?*c.ke_ecs, entity: c.ke_entity, component: c.ke_component_id) callconv(.c) ?*anyopaque {
    const self = self_in orelse return null;
    if (self.handle == null or entity == 0 or component == 0) return null;
    const s = stateOf(self);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return null;

    c.ecs_add_id(s.world, @intCast(entity), @intCast(component));
    // A tag carries no data. Asking for its storage pointer asserts inside the
    // backend, so only sized components resolve to one; a tag yields NULL.
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
    // Guard against unregistered components or dead entities.
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return null;
    if (!c.ecs_has_id(s.world, @intCast(entity), @intCast(component))) return null;
    // ecs_get_id (const) — NOT ecs_get_mut_id — so this is safe inside readonly
    // mode (parallel reads). The mut variant requires a stage and asserts in
    // readonly. The returned pointer is the live storage; the contract exposes it
    // as void* (sim writes through it directly — a plain memory write, not a
    // flecs op, so it is allowed and never adds the component structurally).
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

// ── Resolved multi-term queries (parallel-safe read path) ───────────────────

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
            // Field indices are 0-based, so term t reads field t.
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
    if (s.world) |w| _ = c.ecs_fini(w);

    heap.gpa.destroy(s);
}

// ── Factory ──────────────────────────────────────────────────────────────────

export fn ke_ecs_flecs_create(
    params_in: ?*const c.ke_ecs_flecs_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_ecs_handle {
    _ = params_in;
    const null_handle = std.mem.zeroes(c.ke_ecs_handle);

    installFlecsOsApi();

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = .{
        .api = std.mem.zeroes(c.ke_ecs),
        .world = null,
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

    s.api.handle = s;
    s.api.entity_create = entityCreate;
    s.api.entity_reserve = entityReserve;
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

// ── Tests ────────────────────────────────────────────────────────────────────
//
// flecsAbortHandler itself ends the process by design (E.fatal never
// returns), so it cannot run inside a normal test — these instead cover
// flecsLogHandler, the piece that decides what message survives to be
// printed when it does fire.

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

// The end-to-end case — a genuine flecs internal assertion reaching the real
// abort_ hook and ending the process via E.fatal — needs its own subprocess;
// see abort_probe.zig and abort_integration_test.zig for why and how.

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

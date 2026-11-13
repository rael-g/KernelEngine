//! The `ke_ecs` contract implemented on a flecs world: entities, components registered by name,
//! and multi-component queries resolved into segments of columns.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_ecs_variant = @import("abi_ecs_variant");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_ecs_flecs").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const c = @import("c");
const abi_ecs = @import("abi_ecs");
const abi_ecs_flecs_factory = @import("abi_ecs_flecs_factory");
const abi_result = @import("abi_result");
const field_write = @import("field_write.zig");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.ecs_flecs);

threadlocal var last_msg_buf: [1024]u8 = undefined;
threadlocal var last_msg_len: usize = 0;
threadlocal var flecs_refused: bool = false;

const abort_trace_depth = 32;

/// flecs calls this for each log message, on the thread that logs it. A message at a fatal level is
/// how flecs reports a check it failed, so it marks this thread's current call as refused and is
/// kept in that thread's buffer; a message that does not fit leaves the buffer empty. Other levels
/// are dropped.
fn flecsLogHandler(level: i32, file: [*c]const u8, line: i32, msg: [*c]const u8) callconv(.c) void {
    if (level >= 0 or msg == null) return;
    flecs_refused = true;
    const f: []const u8 = if (file != null) std.mem.span(file) else "?";
    const m: []const u8 = std.mem.span(msg);
    const dst = last_msg_buf[0 .. last_msg_buf.len - 1];
    const written = std.fmt.bufPrint(dst, "{s}:{d}: {s}", .{ f, line, m }) catch dst[0..0];
    last_msg_len = written.len;
}

fn lastMessage() []const u8 {
    return if (last_msg_len > 0) last_msg_buf[0..last_msg_len] else "no message captured";
}

/// Clears this thread's refusal, so the next `outcome` answers only for the flecs calls between
/// the two.
fn begin() void {
    flecs_refused = false;
}

/// The result of the flecs calls since `begin`: ok, or the invalid-argument code with the message
/// flecs gave logged.
fn outcome() abi_result.c.ke_result {
    if (!flecs_refused) return R.ok;
    flecs_refused = false;
    log.warn("flecs refused the call: {s}", .{lastMessage()});
    return R.code(error.InvalidArgument);
}

/// The abort hook flecs calls on an internal failure, one no check of a caller's input reaches.
/// flecs ends the process itself once the hook returns; the hook logs the message this thread
/// captured and the stack at the failure first, so the failure reaches the host's log.
fn flecsAbortHandler() callconv(.c) void {
    var addresses: [abort_trace_depth]usize = undefined;
    const trace = std.debug.captureCurrentStackTrace(.{ .first_address = @returnAddress() }, &addresses);
    log.err("flecs internal failure: {s}{f}", .{ lastMessage(), std.debug.FormatStackTrace{ .stack_trace = trace } });
}

var os_api_installed: bool = false;

/// Replaces the flecs OS table once per process, so every world created afterwards shares these
/// hooks. It runs before the world is initialized, so flecs reports through them from its first
/// call.
fn installFlecsOsApi() void {
    if (os_api_installed) return;
    c.ecs_os_set_api_defaults();
    var api = c.ecs_os_get_api();
    api.log_ = flecsLogHandler;
    api.abort_ = flecsAbortHandler;
    c.ecs_os_set_api(&api);
    os_api_installed = true;
}

/// One slot of the per-component query cache in `State.queries`. The query is owned by the state
/// and finalized by `destroy`.
const QueryCacheEntry = struct {
    cid: abi_asset_resolver.c.ke_component_id,
    query: ?*c.ecs_query_t,
};

/// One remembered field table, copied at registration with every name and string it reaches, so
/// the caller's table only has to live for the call; freed with the state.
const LayoutEntry = struct {
    cid: abi_asset_resolver.c.ke_component_id,
    fields: [*]const abi_ecs.c.ke_component_field,
    field_count: u32,
};

fn dupText(text: ?[*:0]const u8) error{OutOfMemory}!?[*:0]const u8 {
    const t = text orelse return null;
    return (try heap.gpa.dupeZ(u8, std.mem.span(t))).ptr;
}

fn freeText(text: ?[*:0]const u8) void {
    if (text) |t| heap.gpa.free(std.mem.span(t)[0 .. std.mem.len(t) + 1]);
}

fn freeFields(fields: []abi_ecs.c.ke_component_field) void {
    for (fields) |f| {
        freeText(f.name);
        if (f.default_value.type == abi_ecs_variant.c.KE_VARIANT_STRING) freeText(f.default_value.unnamed_0.s);
        if (f.enum_names) |names| {
            const list: [*]const ?[*:0]const u8 = @ptrCast(names);
            for (list[0..f.enum_count]) |n| freeText(n);
            heap.gpa.free(list[0..f.enum_count]);
        }
    }
    heap.gpa.free(fields);
}

fn copyFields(source: []const abi_ecs.c.ke_component_field) error{OutOfMemory}![]abi_ecs.c.ke_component_field {
    const fields = try heap.gpa.alloc(abi_ecs.c.ke_component_field, source.len);
    for (fields, source) |*f, from| f.* = .{ .name = null, .type = from.type, .offset = from.offset, .size = from.size, .default_value = from.default_value, .enum_names = null, .enum_count = 0 };
    errdefer freeFields(fields);
    for (fields, source) |*f, from| {
        if (from.default_value.type == abi_ecs_variant.c.KE_VARIANT_STRING) {
            f.default_value.unnamed_0.s = null;
            f.default_value.unnamed_0.s = try dupText(from.default_value.unnamed_0.s);
        }
        f.name = try dupText(from.name);
        if (from.enum_count == 0) continue;
        if (from.enum_names) |names| {
            const copied = try heap.gpa.alloc(?[*:0]const u8, from.enum_count);
            @memset(copied, null);
            f.enum_names = @ptrCast(copied.ptr);
            f.enum_count = from.enum_count;
            const list: [*]const ?[*:0]const u8 = @ptrCast(names);
            for (copied, list[0..from.enum_count]) |*n, name| n.* = try dupText(name);
        }
    }
    return fields;
}

/// A query registered by `queryRegister`, with the copy of its description that later
/// registrations are compared with. It owns `elem_sizes`, one size per term, and the three copied
/// arrays, and `destroy` frees them.
const RegisteredQuery = struct {
    query: ?*c.ecs_query_t,
    elem_sizes: []usize,
    terms: []abi_ecs.c.ke_ecs_query_term,
    with: []abi_asset_resolver.c.ke_component_id,
    without: []abi_asset_resolver.c.ke_component_id,
    track_changes: bool,
    term_count: usize,
};

fn freeRegistered(rq: *const RegisteredQuery) void {
    heap.gpa.free(rq.elem_sizes);
    heap.gpa.free(rq.terms);
    heap.gpa.free(rq.with);
    heap.gpa.free(rq.without);
}

const test_config: abi_ecs.c.ke_ecs_config = .{ .reserved_id_capacity = 1048576 };

/// The state behind `api.handle`, made by `ke_ecs_flecs_create` and freed by `destroy`. The world
/// has two sources of entity ids that never meet: flecs's own allocator, moved to start at
/// `ke_ecs_config.reserved_id_capacity` and serving `entityCreate`, and the pool of ids from
/// `reserve_low` up to `reserve_end`, below that split, handed out by `entityReserve` with the
/// atomic counter `reserve_next`. A reserved id is only a number until `materializeReserved`
/// makes it alive, once; the `materialized` bitmap, one bit per pool slot, is what keeps a
/// destroyed reserved entity from being revived. `layouts` holds the first field table seen for
/// each component name, which later registrations are compared with and which seeds defaults on
/// attach. `queries` holds one cached query per component and `rqueries` the queries made by
/// `queryRegister`, whose id is the index plus one. `materialized` and the three arrays stay null
/// until something first needs them. `singletons` is a disabled entity, which no query matches,
/// holding the world's singleton components. Nothing here is locked and no thread is started; only
/// `reserve_next` is touched by several threads.
const State = struct {
    api: abi_ecs.c.ke_ecs,
    world: ?*c.ecs_world_t,
    singletons: c.ecs_entity_t,

    reserve_low: u32,
    reserve_end: u32,
    reserve_next: std.atomic.Value(u32),
    materialized: ?[]u8,

    queries: ?[*]QueryCacheEntry,
    query_count: usize,
    query_capacity: usize,

    rqueries: ?[*]RegisteredQuery,
    rquery_count: usize,
    rquery_capacity: usize,

    layouts: ?[*]LayoutEntry,
    layout_count: usize,
    layout_capacity: usize,

    ids: std.ArrayListUnmanaged(c.ecs_id_t) = .empty,
    cids: std.AutoHashMapUnmanaged(c.ecs_id_t, abi_asset_resolver.c.ke_component_id) = .empty,
    trackers: std.ArrayListUnmanaged(*Tracker) = .empty,
    next_user: u32 = 0,
    user_start: u32 = 0,
    own_range: ?*const c.ecs_entity_range_t = null,
    user_range: ?*const c.ecs_entity_range_t = null,
};

/// Makes an entity of the created band alive under the band's range, flecs's own range active again
/// afterwards.
fn makeUserAlive(s: *State, e: c.ecs_entity_t) void {
    c.ecs_entity_range_set(s.world, s.user_range);
    _ = c.ecs_make_alive(s.world, e);
    c.ecs_entity_range_set(s.world, s.own_range);
}

const user_id_start: u32 = 1 << 28;
const user_id_end: u32 = std.math.maxInt(u32);

/// The entities that lost one component since the last `removals` call, filled by a flecs
/// observer of `OnRemove` on the component's flecs id.
const Tracker = struct {
    cid: abi_asset_resolver.c.ke_component_id,
    singletons: c.ecs_entity_t,
    observer: c.ecs_entity_t = 0,
    lost: std.ArrayListUnmanaged(abi_asset_resolver.c.ke_entity) = .empty,
};

/// The flecs id behind a component id, zero for an unknown one.
fn idOf(s: *State, cid: abi_asset_resolver.c.ke_component_id) c.ecs_id_t {
    if (cid == 0 or cid > s.ids.items.len) return 0;
    return s.ids.items[cid - 1];
}

/// The component id of a flecs id, given the next free one the first time the id is seen.
fn cidFor(s: *State, id: c.ecs_id_t) error{OutOfMemory}!abi_asset_resolver.c.ke_component_id {
    if (s.cids.get(id)) |cid| return cid;
    try s.ids.append(heap.gpa, id);
    errdefer _ = s.ids.pop();
    const cid: abi_asset_resolver.c.ke_component_id = @intCast(s.ids.items.len);
    try s.cids.put(heap.gpa, id, cid);
    return cid;
}

fn pairFirst(id: c.ecs_id_t) c.ecs_entity_t {
    return (id & 0x00FF_FFFF_FFFF_FFFF) >> 32;
}

fn pairSecond(id: c.ecs_id_t) c.ecs_entity_t {
    return id & 0xFFFF_FFFF;
}

/// The component whose storage and field table a component id uses: the relation of a pair, the
/// component itself otherwise.
fn storageOf(s: *State, cid: abi_asset_resolver.c.ke_component_id) abi_asset_resolver.c.ke_component_id {
    const id = idOf(s, cid);
    if (id == 0 or !c.ecs_id_is_pair(id)) return cid;
    return s.cids.get(pairFirst(id)) orelse cid;
}

fn stateOf(self: *abi_ecs.c.ke_ecs) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// Returns the cached query for `cid`, creating it on first request. Returns null when the cache
/// cannot grow or flecs refuses the query, and the cached entries are left as they were. The
/// returned pointer points into `queries` and is invalidated by the next growth of that array.
fn findOrCreateQuery(s: *State, cid: abi_asset_resolver.c.ke_component_id) ?*QueryCacheEntry {
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
    desc.terms[0].id = idOf(s, cid);
    const q = c.ecs_query_init(s.world, &desc) orelse return null;

    const entry = &s.queries.?[s.query_count];
    s.query_count += 1;
    entry.* = .{ .cid = cid, .query = q };
    return entry;
}

/// Two null names are equal; a null and a non-null name are not.
fn nameEquals(a: [*c]const u8, b: [*c]const u8) bool {
    if (a == null or b == null) return a == b;
    return std.mem.orderZ(u8, @ptrCast(a), @ptrCast(b)) == .eq;
}

/// Index of the first field where two tables disagree in type, offset, size or name, or the length
/// of the shorter table when only the lengths differ. Null when the tables are identical.
fn firstLayoutDiff(a: []const abi_ecs.c.ke_component_field, b: []const abi_ecs.c.ke_component_field) ?usize {
    const common = @min(a.len, b.len);
    for (0..common) |i| {
        if (a[i].type != b[i].type or a[i].offset != b[i].offset or a[i].size != b[i].size) return i;
        if (!nameEquals(a[i].name, b[i].name)) return i;
    }
    return if (a.len != b.len) common else null;
}

/// Whether every field ends within `element_size` bytes.
fn layoutFitsSize(fields: []const abi_ecs.c.ke_component_field, element_size: usize) bool {
    for (fields) |f| {
        if (@as(usize, f.offset) + @as(usize, f.size) > element_size) return false;
    }
    return true;
}

/// The field table remembered for `cid`, or null when none was ever recorded.
fn isRegistered(s: *State, cid: abi_asset_resolver.c.ke_component_id) bool {
    const qs = s.queries orelse return false;
    for (qs[0..s.query_count]) |q| if (q.cid == cid) return true;
    return false;
}

fn layoutOf(s: *State, cid: abi_asset_resolver.c.ke_component_id) ?[]const abi_ecs.c.ke_component_field {
    const ls = s.layouts orelse return null;
    for (0..s.layout_count) |i| {
        if (ls[i].cid == cid) return ls[i].fields[0..ls[i].field_count];
    }
    return null;
}

/// Records a copy of the field table for `cid`, growing `layouts` when full. Returns false, leaving
/// the registry as it was, when memory runs out.
fn rememberLayout(
    s: *State,
    cid: abi_asset_resolver.c.ke_component_id,
    fields: [*]const abi_ecs.c.ke_component_field,
    field_count: u32,
) bool {
    const copied = copyFields(fields[0..field_count]) catch return false;
    if (s.layout_count == s.layout_capacity) {
        const new_cap: usize = if (s.layout_capacity != 0) s.layout_capacity * 2 else 8;
        const new_buf = heap.gpa.alloc(LayoutEntry, new_cap) catch {
            freeFields(copied);
            return false;
        };
        if (s.layouts) |old| {
            @memcpy(new_buf[0..s.layout_count], old[0..s.layout_count]);
            heap.gpa.free(old[0..s.layout_capacity]);
        }
        s.layouts = new_buf.ptr;
        s.layout_capacity = new_cap;
    }
    s.layouts.?[s.layout_count] = .{ .cid = cid, .fields = copied.ptr, .field_count = field_count };
    s.layout_count += 1;
    return true;
}

/// Slot `entity_create`. Ids come from `next_user`, counted up from `user_id_start`, the first id
/// flecs never gives a component, and never reused, so a snapshot restores them by restoring the
/// counter; flecs's own allocator serves its internal entities between `reserved_id_capacity` and
/// `user_id_start`.
fn entityCreate(self_in: ?*abi_ecs.c.ke_ecs, out_entity: ?*abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const out = out_entity orelse return R.code(error.InvalidArgument);
    out.* = 0;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    if (s.next_user >= user_id_end) {
        log.warn("every entity id below {d} was created", .{user_id_end});
        return R.code(error.OutOfMemory);
    }
    const e: c.ecs_entity_t = s.next_user;
    begin();
    makeUserAlive(s, e);
    const rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;
    s.next_user += 1;
    out.* = @intCast(e);
    return R.ok;
}

/// Slot `entity_reserve`. Hands out the next id of the reserve pool. The id is not alive in the
/// world until `materializeReserved` runs for it. It takes no lock and calls nothing of flecs, so
/// threads may call it concurrently.
fn entityReserve(self_in: ?*abi_ecs.c.ke_ecs, out_entity: ?*abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const out = out_entity orelse return R.code(error.InvalidArgument);
    out.* = 0;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const offset = s.reserve_next.fetchAdd(1, .monotonic);
    if (offset >= s.reserve_end - s.reserve_low) {
        log.warn("every id below reserved_id_capacity {d} was reserved", .{s.reserve_end});
        return R.code(error.OutOfMemory);
    }
    out.* = @as(abi_asset_resolver.c.ke_entity, s.reserve_low) + offset;
    return R.ok;
}

/// Slot `entity_materialize`. Brings a reserved id alive in the world through
/// `materializeReserved`. An id outside the pool is left alone.
fn entityMaterialize(self_in: ?*abi_ecs.c.ke_ecs, entity: abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or entity == 0) return R.code(error.InvalidArgument);
    begin();
    materializeReserved(stateOf(self), entity) catch |err| return R.code(err);
    return outcome();
}

/// Makes a reserved id alive in flecs, and only the first call for its slot does. The bit recorded
/// in `materialized` is the only memory of that call, so a reserved entity destroyed later is not
/// revived. If the bitmap cannot be allocated, nothing is recorded and the id stays dead.
fn materializeReserved(s: *State, entity: abi_asset_resolver.c.ke_entity) error{OutOfMemory}!void {
    if (entity < s.reserve_low or entity >= s.reserve_end) return;

    const bits = s.materialized orelse blk: {
        const bytes = ((s.reserve_end - s.reserve_low) + 7) / 8;
        const buf = heap.gpa.alloc(u8, bytes) catch {
            log.warn("materializing entity {d} failed: out of memory", .{entity});
            return error.OutOfMemory;
        };
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

/// Slot `entity_destroy`. Deletes a living entity; a dead id is left alone. A reserved id that is
/// destroyed stays dead, because its slot in `materialized` is already set.
fn entityDestroy(self_in: ?*abi_ecs.c.ke_ecs, entity: abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or entity == 0) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    begin();
    if (c.ecs_is_alive(s.world, @intCast(entity))) c.ecs_delete(s.world, @intCast(entity));
    return outcome();
}

/// Slot `component_register`. The params are checked first: a missing name, an alignment that is
/// not a power of two, or a field table that does not fit the size registers nothing. For a name
/// that already exists, the size and the alignment are compared before the layout, and a failure
/// changes nothing. For a new name, a failed layout allocation leaves the component registered in
/// the world, and a retry by name then finds it and remembers the table. On failure the id written
/// is zero and what disagrees is logged.
fn componentRegister(
    self_in: ?*abi_ecs.c.ke_ecs,
    params: [*c]const abi_ecs.c.ke_component_params,
    out_cid: ?*abi_asset_resolver.c.ke_component_id,
) callconv(.c) abi_result.c.ke_result {
    const out = out_cid orelse return R.code(error.InvalidArgument);
    out.* = 0;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or params == null or params.*.name == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const name = params.*.name.?;
    const size = params.*.size;
    const alignment: usize = params.*.alignment;
    if (size != 0 and (alignment == 0 or !std.math.isPowerOfTwo(alignment))) {
        return refuse("component '{s}': alignment {d} is not a power of two", .{ name, alignment });
    }
    const fields = params.*.fields;
    const field_count = params.*.field_count;

    const incoming: ?[]const abi_ecs.c.ke_component_field =
        if (fields != null and field_count > 0) fields.?[0..field_count] else null;

    if (incoming) |inc| {
        if (!layoutFitsSize(inc, size)) {
            return refuse("component '{s}': field table describes bytes past its {d}-byte size", .{ name, size });
        }
    }

    const existing = c.ecs_lookup(s.world, name);
    if (existing != 0) {
        const cid = cidFor(s, existing) catch return R.code(error.OutOfMemory);
        const ti = c.ecs_get_type_info(s.world, @intCast(existing));
        const existing_size: usize = if (ti != null) @intCast(ti.*.size) else 0;
        const existing_alignment: usize = if (ti != null and size != 0) @intCast(ti.*.alignment) else alignment;
        const same_shape = existing_size == size and (size == 0 or existing_alignment == alignment);
        if (incoming) |inc| {
            if (layoutOf(s, cid)) |prev| {
                if (!same_shape or firstLayoutDiff(prev, inc) != null) {
                    migrate(s, cid, name, size, alignment, inc) catch |err| {
                        log.warn("migrating component '{s}' to its new layout failed: {t}", .{ name, err });
                        return R.code(err);
                    };
                }
            } else if (!same_shape) {
                return refuse("component '{s}' already registered as {d} bytes aligned to {d}, now {d} aligned to {d}, with no field table to migrate by", .{ name, existing_size, existing_alignment, size, alignment });
            } else if (!rememberLayout(s, cid, inc.ptr, field_count)) {
                log.warn("registering component '{s}' failed: out of memory", .{name});
                return R.code(error.OutOfMemory);
            }
        } else if (!same_shape) {
            return refuse("component '{s}' already registered as {d} bytes aligned to {d}, now {d} aligned to {d}, with no field table to migrate by", .{ name, existing_size, existing_alignment, size, alignment });
        }
        _ = findOrCreateQuery(s, cid);
        out.* = cid;
        return R.ok;
    }

    var edesc: c.ecs_entity_desc_t = std.mem.zeroes(c.ecs_entity_desc_t);
    edesc.name = name;
    begin();
    const e = c.ecs_entity_init(s.world, &edesc);
    var rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;

    if (size == 0) {
        const tag = cidFor(s, e) catch return R.code(error.OutOfMemory);
        _ = findOrCreateQuery(s, tag);
        out.* = tag;
        return R.ok;
    }

    var cdesc: c.ecs_component_desc_t = std.mem.zeroes(c.ecs_component_desc_t);
    cdesc.entity = e;
    cdesc.type.size = @intCast(size);
    cdesc.type.alignment = @intCast(alignment);
    const created_id = c.ecs_component_init(s.world, &cdesc);
    rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;
    const cid = cidFor(s, created_id) catch return R.code(error.OutOfMemory);

    if (incoming) |inc| {
        if (!rememberLayout(s, cid, inc.ptr, field_count)) {
            log.warn("registering component '{s}' failed: out of memory", .{name});
            return R.code(error.OutOfMemory);
        }
    }

    _ = findOrCreateQuery(s, cid);
    out.* = cid;
    return R.ok;
}

/// Moves a component to a new layout under the same component id: a new flecs component takes the
/// name, every holder and the singleton get it seeded with the new defaults and the fields of the
/// same name, type and size copied from the old one, which is then removed and deleted; the field
/// table, the cached query, the registered queries and the removal observers that name the
/// component are rebuilt on the new flecs id.
fn migrate(s: *State, cid: abi_asset_resolver.c.ke_component_id, name: [*:0]const u8, size: usize, alignment: usize, inc: []const abi_ecs.c.ke_component_field) error{ OutOfMemory, InvalidArgument }!void {
    const old_id = idOf(s, cid);
    const old_fields = try copyFields(layoutOf(s, cid).?);
    defer freeFields(old_fields);
    const new_fields = try copyFields(inc);
    errdefer freeFields(new_fields);
    const old_ti = c.ecs_get_type_info(s.world, old_id);
    const old_size: usize = if (old_ti != null) @intCast(old_ti.*.size) else 0;

    begin();
    _ = c.ecs_set_name(s.world, old_id, null);
    var edesc: c.ecs_entity_desc_t = std.mem.zeroes(c.ecs_entity_desc_t);
    edesc.name = name;
    var new_id = c.ecs_entity_init(s.world, &edesc);
    if (size != 0) {
        var cdesc: c.ecs_component_desc_t = std.mem.zeroes(c.ecs_component_desc_t);
        cdesc.entity = new_id;
        cdesc.type.size = @intCast(size);
        cdesc.type.alignment = @intCast(alignment);
        new_id = c.ecs_component_init(s.world, &cdesc);
    }
    if (outcome() != abi_result.c.KE_OK or new_id == 0) return error.InvalidArgument;

    for (s.trackers.items) |t| if (t.cid == cid and t.observer != 0) {
        c.ecs_delete(s.world, t.observer);
        t.observer = 0;
    };

    var holders: std.ArrayListUnmanaged(c.ecs_entity_t) = .empty;
    defer holders.deinit(heap.gpa);
    var desc: c.ecs_query_desc_t = std.mem.zeroes(c.ecs_query_desc_t);
    desc.terms[0].id = old_id;
    const q = c.ecs_query_init(s.world, &desc) orelse return error.InvalidArgument;
    var it = c.ecs_query_iter(s.world, q);
    while (c.ecs_query_next(&it)) for (it.entities[0..@intCast(it.count)]) |e| try holders.append(heap.gpa, e);
    c.ecs_query_fini(q);
    if (c.ecs_has_id(s.world, s.singletons, old_id)) try holders.append(heap.gpa, s.singletons);

    const scratch = try heap.gpa.alloc(u8, @max(old_size, 1));
    defer heap.gpa.free(scratch);
    for (holders.items) |e| {
        if (old_size != 0) @memcpy(scratch[0..old_size], @as([*]const u8, @ptrCast(c.ecs_get_id(s.world, e, old_id)))[0..old_size]);
        c.ecs_add_id(s.world, e, new_id);
        if (size != 0) {
            const dst: [*]u8 = @ptrCast(c.ecs_get_mut_id(s.world, e, new_id));
            @memset(dst[0..size], 0);
            field_write.seedDefaults(dst, new_fields.ptr, @intCast(new_fields.len));
            for (new_fields) |nf| for (old_fields) |of| {
                if (!nameEquals(nf.name, of.name) or nf.type != of.type or nf.size != of.size) continue;
                @memcpy(dst[nf.offset..][0..nf.size], scratch[of.offset..][0..of.size]);
            };
        }
        c.ecs_remove_id(s.world, e, old_id);
    }
    c.ecs_delete(s.world, old_id);

    s.ids.items[cid - 1] = new_id;
    _ = s.cids.remove(old_id);
    try s.cids.put(heap.gpa, new_id, cid);
    const ls = s.layouts.?;
    for (ls[0..s.layout_count]) |*l| if (l.cid == cid) {
        freeFields(@constCast(l.fields[0..l.field_count]));
        l.fields = new_fields.ptr;
        l.field_count = @intCast(new_fields.len);
    };

    if (s.queries) |qs| for (qs[0..s.query_count]) |*entry| if (entry.cid == cid) {
        if (entry.query) |old| c.ecs_query_fini(old);
        var d: c.ecs_query_desc_t = std.mem.zeroes(c.ecs_query_desc_t);
        d.terms[0].id = new_id;
        entry.query = c.ecs_query_init(s.world, &d);
    };
    if (s.rqueries) |rqs| for (rqs[0..s.rquery_count]) |*rq| {
        if (!namesComponent(rq, cid)) continue;
        if (rq.query) |old| c.ecs_query_fini(old);
        rq.query = buildQuery(s, rq.terms, rq.with, rq.without, rq.track_changes);
        for (rq.terms, rq.elem_sizes) |t, *elem| {
            const ti = c.ecs_get_type_info(s.world, idOf(s, t.component));
            elem.* = if (ti != null) @intCast(ti.*.size) else 0;
        }
    };
    for (s.trackers.items) |t| if (t.cid == cid) try observe(s, t);
}

fn namesComponent(rq: *const RegisteredQuery, cid: abi_asset_resolver.c.ke_component_id) bool {
    for (rq.terms) |t| if (t.component == cid) return true;
    for (rq.with) |w| if (w == cid) return true;
    for (rq.without) |w| if (w == cid) return true;
    return false;
}

fn buildQuery(s: *State, terms: []const abi_ecs.c.ke_ecs_query_term, with: []const abi_asset_resolver.c.ke_component_id, without: []const abi_asset_resolver.c.ke_component_id, track_changes: bool) ?*c.ecs_query_t {
    var fdesc: c.ecs_query_desc_t = std.mem.zeroes(c.ecs_query_desc_t);
    for (terms, 0..) |t, i| {
        fdesc.terms[i].id = idOf(s, t.component);
        fdesc.terms[i].inout = if ((@as(c_uint, @intCast(t.access)) & abi_ecs.c.KE_ECS_ACCESS_WRITE) != 0) c.EcsInOut else c.EcsIn;
    }
    for (with, terms.len..) |cid, i| {
        fdesc.terms[i].id = idOf(s, cid);
        fdesc.terms[i].inout = c.EcsInOutNone;
    }
    for (without, terms.len + with.len..) |cid, i| {
        fdesc.terms[i].id = idOf(s, cid);
        fdesc.terms[i].oper = c.EcsNot;
    }
    if (track_changes) fdesc.flags = c.EcsQueryDetectChanges;
    return c.ecs_query_init(s.world, &fdesc);
}

/// Logs why a registration was refused and returns the invalid-argument code.
fn refuse(comptime fmt: []const u8, args: anytype) abi_result.c.ke_result {
    log.warn(fmt, args);
    return R.code(error.InvalidArgument);
}

/// Slot `component_lookup`. Reports the id and size of the component called by name through
/// out_meta, with the remembered field table when there is one and a null table otherwise; a tag
/// registered with size 0 reports size and alignment 0. A null out_meta only checks that the name
/// exists. An unknown name, an entity never registered as a component, and a null argument answer
/// false.
fn componentLookup(
    self_in: ?*abi_ecs.c.ke_ecs,
    name: [*c]const u8,
    out_meta: [*c]abi_ecs.c.ke_component_meta,
) callconv(.c) bool {
    const self = self_in orelse return false;
    if (self.handle == null or name == null) return false;
    const s = stateOf(self);

    const e = c.ecs_lookup(s.world, name);
    if (e == 0) return false;

    const cid = s.cids.get(e) orelse return false;
    const ti = c.ecs_get_type_info(s.world, @intCast(e));
    if (ti == null and !isRegistered(s, cid)) return false;

    if (out_meta != null) {
        out_meta.*.cid = cid;
        out_meta.*.size = if (ti != null) @intCast(ti.*.size) else 0;
        out_meta.*.alignment = if (ti != null) @intCast(ti.*.alignment) else 0;
        if (layoutOf(s, cid)) |f| {
            out_meta.*.fields = f.ptr;
            out_meta.*.field_count = @intCast(f.len);
        } else {
            out_meta.*.fields = null;
            out_meta.*.field_count = 0;
        }
    }
    return true;
}

/// Slot `component_add`. The bytes are zeroed and seeded with the remembered defaults only on the
/// attach that adds the component; attaching a component the entity already holds returns its bytes
/// unchanged. A zero-size component is added and yields null. A reserved id is materialized first,
/// and an entity still not alive after that is refused.
fn componentAdd(
    self_in: ?*abi_ecs.c.ke_ecs,
    entity: abi_asset_resolver.c.ke_entity,
    component: abi_asset_resolver.c.ke_component_id,
    out_data: ?*?*anyopaque,
) callconv(.c) abi_result.c.ke_result {
    const out = out_data orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or entity == 0 or component == 0) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    begin();
    materializeReserved(s, entity) catch |err| return R.code(err);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) {
        log.warn("attaching component {d} to entity {d}, which is not alive", .{ component, entity });
        return R.code(error.InvalidArgument);
    }
    return attachTo(s, @intCast(entity), component, out);
}

/// Adds a component to a living entity, zeroing and seeding it with the remembered defaults only
/// when the entity did not hold it, and writes its bytes, or null for a zero-size component.
fn attachTo(s: *State, entity: c.ecs_entity_t, component: abi_asset_resolver.c.ke_component_id, out: *?*anyopaque) abi_result.c.ke_result {
    const id = idOf(s, component);
    if (id == 0) {
        log.warn("no component has id {d}", .{component});
        return R.code(error.InvalidArgument);
    }
    const already_had = c.ecs_has_id(s.world, entity, id);
    c.ecs_add_id(s.world, entity, id);
    var rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;
    const ti = c.ecs_get_type_info(s.world, id);
    if (ti == null or ti.*.size <= 0) return R.ok;

    const slot = c.ecs_get_mut_id(s.world, entity, id);
    rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;
    if (!already_had) {
        const bytes: [*]u8 = @ptrCast(slot);
        @memset(bytes[0..@intCast(ti.*.size)], 0);
        if (layoutOf(s, storageOf(s, component))) |fields| {
            field_write.seedDefaults(slot, fields.ptr, @intCast(fields.len));
        }
    }
    out.* = slot;
    return R.ok;
}

/// Slot `component_remove`. Removes a component from a living entity. An entity that is not alive
/// is left alone.
fn componentRemove(self_in: ?*abi_ecs.c.ke_ecs, entity: abi_asset_resolver.c.ke_entity, component: abi_asset_resolver.c.ke_component_id) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or entity == 0 or component == 0) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    begin();
    const id = idOf(s, component);
    if (id != 0 and c.ecs_is_alive(s.world, @intCast(entity))) c.ecs_remove_id(s.world, @intCast(entity), id);
    return outcome();
}

/// Slot `component_get`. The bytes of a component for a living entity that holds it, otherwise
/// null.
fn componentGet(self_in: ?*abi_ecs.c.ke_ecs, entity: abi_asset_resolver.c.ke_entity, component: abi_asset_resolver.c.ke_component_id) callconv(.c) ?*anyopaque {
    const self = self_in orelse return null;
    if (self.handle == null or entity == 0 or component == 0) return null;
    const s = stateOf(self);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return null;
    const id = idOf(s, component);
    if (id == 0 or !c.ecs_has_id(s.world, @intCast(entity), id)) return null;
    return @constCast(c.ecs_get_id(s.world, @intCast(entity), id));
}

/// Slot `component_size`. The byte size flecs holds for a component id, zero for an unknown id or
/// a tag.
fn componentSize(self_in: ?*abi_ecs.c.ke_ecs, cid: abi_asset_resolver.c.ke_component_id) callconv(.c) usize {
    const self = self_in orelse return 0;
    if (self.handle == null or cid == 0) return 0;
    const s = stateOf(self);
    const id = idOf(s, cid);
    if (id == 0) return 0;
    const ti = c.ecs_get_type_info(s.world, id);
    if (ti == null) return 0;
    return @intCast(ti.*.size);
}

/// Slot `component_field_write`. Converts and writes through `field_write`, which holds no state,
/// so the ecs only refuses a null argument or a value the conversion refuses.
fn componentFieldWrite(self_in: ?*abi_ecs.c.ke_ecs, component: ?*anyopaque, place: ?*const abi_ecs.c.ke_component_field, value: ?*const abi_ecs_variant.c.ke_variant) callconv(.c) abi_result.c.ke_result {
    _ = self_in orelse return R.code(error.InvalidArgument);
    if (!field_write.write(component, place, value)) return R.code(error.InvalidArgument);
    return R.ok;
}

/// Slot `query_register`. Builds a flecs query with one term per description term, reading as
/// `EcsIn` or writing as `EcsInOut`, one data-less term per `with` component and one `EcsNot` term
/// per `without` component, cached with change detection when the description tracks changes; and
/// records the byte size of each term for `queryResolve`. A description registered before, tracking
/// no changes, answers the id it got then and builds nothing. The id counts from one, so it is never
/// the invalid id. A null argument, no terms, a term with no access or an unknown one, more terms
/// than a flecs query has and a query flecs refuses are invalid arguments; a flecs query created
/// before a later step fails is finalized first.
fn queryRegister(
    self_in: ?*abi_ecs.c.ke_ecs,
    desc_in: ?*const abi_ecs.c.ke_ecs_query_desc,
    out_query: ?*abi_ecs.c.ke_query_id,
) callconv(.c) abi_result.c.ke_result {
    const out = out_query orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_QUERY_INVALID;
    const self = self_in orelse return R.code(error.InvalidArgument);
    const d = desc_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or d.terms == null or d.term_count == 0) return R.code(error.InvalidArgument);
    if ((d.with_count != 0 and d.with == null) or (d.without_count != 0 and d.without == null)) return R.code(error.InvalidArgument);
    const terms = d.terms.?[0..d.term_count];
    const with: []const abi_asset_resolver.c.ke_component_id = if (d.with_count == 0) &.{} else d.with.?[0..d.with_count];
    const without: []const abi_asset_resolver.c.ke_component_id = if (d.without_count == 0) &.{} else d.without.?[0..d.without_count];
    const access_mask: c_uint = abi_ecs.c.KE_ECS_ACCESS_READ | abi_ecs.c.KE_ECS_ACCESS_WRITE;
    for (terms, 0..) |t, i| {
        if (t.access == 0 or (@as(c_uint, @intCast(t.access)) & ~access_mask) != 0) {
            log.warn("query term {d} has the access {d}, which is neither read nor write", .{ i, t.access });
            return R.code(error.InvalidArgument);
        }
    }
    const fdesc: c.ecs_query_desc_t = std.mem.zeroes(c.ecs_query_desc_t);
    const total = terms.len + with.len + without.len;
    if (total > fdesc.terms.len) {
        log.warn("a query of {d} terms and filters is more than the {d} a flecs query holds", .{ total, fdesc.terms.len });
        return R.code(error.InvalidArgument);
    }
    const s = stateOf(self);

    if (!d.track_changes) if (s.rqueries) |existing| {
        for (existing[0..s.rquery_count], 1..) |*rq, id| {
            if (rq.track_changes) continue;
            if (!std.mem.eql(u8, std.mem.sliceAsBytes(rq.terms), std.mem.sliceAsBytes(terms))) continue;
            if (!std.mem.eql(abi_asset_resolver.c.ke_component_id, rq.with, with)) continue;
            if (!std.mem.eql(abi_asset_resolver.c.ke_component_id, rq.without, without)) continue;
            out.* = @intCast(id);
            return R.ok;
        }
    };

    begin();
    const query = buildQuery(s, terms, with, without, d.track_changes);
    const rc = outcome();
    const q = query orelse {
        if (rc == abi_result.c.KE_OK) log.warn("flecs refused the query", .{});
        return R.code(error.InvalidArgument);
    };
    if (rc != abi_result.c.KE_OK) {
        c.ecs_query_fini(q);
        return rc;
    }
    var rq: RegisteredQuery = .{ .query = q, .elem_sizes = &.{}, .terms = &.{}, .with = &.{}, .without = &.{}, .track_changes = d.track_changes, .term_count = terms.len };
    copyDescription(&rq, terms, with, without) catch {
        freeRegistered(&rq);
        c.ecs_query_fini(q);
        return R.code(error.OutOfMemory);
    };
    for (terms, rq.elem_sizes) |t, *size| {
        const ti = c.ecs_get_type_info(s.world, idOf(s, t.component));
        size.* = if (ti != null) @intCast(ti.*.size) else 0;
    }

    if (s.rquery_count == s.rquery_capacity) {
        const new_cap: usize = if (s.rquery_capacity != 0) s.rquery_capacity * 2 else 8;
        const new_buf = heap.gpa.alloc(RegisteredQuery, new_cap) catch {
            freeRegistered(&rq);
            c.ecs_query_fini(q);
            return R.code(error.OutOfMemory);
        };
        if (s.rqueries) |old| {
            @memcpy(new_buf[0..s.rquery_count], old[0..s.rquery_count]);
            heap.gpa.free(old[0..s.rquery_capacity]);
        }
        s.rqueries = new_buf.ptr;
        s.rquery_capacity = new_cap;
    }

    s.rqueries.?[s.rquery_count] = rq;
    s.rquery_count += 1;
    out.* = @intCast(s.rquery_count);
    return R.ok;
}

fn copyDescription(
    rq: *RegisteredQuery,
    terms: []const abi_ecs.c.ke_ecs_query_term,
    with: []const abi_asset_resolver.c.ke_component_id,
    without: []const abi_asset_resolver.c.ke_component_id,
) error{OutOfMemory}!void {
    rq.elem_sizes = try heap.gpa.alloc(usize, terms.len);
    rq.terms = try heap.gpa.dupe(abi_ecs.c.ke_ecs_query_term, terms);
    rq.with = try heap.gpa.dupe(abi_asset_resolver.c.ke_component_id, with);
    rq.without = try heap.gpa.dupe(abi_asset_resolver.c.ke_component_id, without);
}

/// Slot `query_resolve`. Runs the query from its start and writes one segment per matching table:
/// its entities, its count, one column per term, with the columns of segment n starting at n times
/// the term count in the caller's array, and whether the table changed for a query tracking
/// changes. flecs marks the written columns of a table changed, and moves the query's view of it
/// forward, when the iteration leaves the table. Column pointers refer into the world's storage and
/// stay valid until the next structural change, and a zero-size term's column is null. Segments
/// beyond the caller's capacity are counted but skipped, keeping their changes, so the count written
/// to out_count is the total. Any invalid argument or unknown query leaves that count at zero.
fn queryResolve(
    self_in: ?*abi_ecs.c.ke_ecs,
    query: abi_ecs.c.ke_query_id,
    out_segments: [*c]abi_ecs.c.ke_ecs_segment,
    max_segments: usize,
    out_columns: [*c]?*anyopaque,
    out_matched: [*c]abi_asset_resolver.c.ke_component_id,
    out_count: [*c]usize,
) callconv(.c) abi_result.c.ke_result {
    if (out_count == null) return R.code(error.InvalidArgument);
    out_count.* = 0;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or query == abi_ecs.c.KE_QUERY_INVALID or out_segments == null or out_columns == null or out_matched == null or max_segments == 0)
        return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const idx: usize = @intCast(query - 1);
    if (idx >= s.rquery_count) {
        log.warn("no query has id {d}", .{query});
        return R.code(error.InvalidArgument);
    }
    const rq = &s.rqueries.?[idx];
    const q = rq.query orelse return R.code(error.InvalidArgument);

    begin();
    var seg: usize = 0;
    var it = c.ecs_query_iter(s.world, q);
    while (c.ecs_query_next(&it)) {
        if (seg >= max_segments) {
            c.ecs_iter_skip(&it);
            seg += 1;
            continue;
        }
        const dst = &out_segments[seg];
        dst.entities = @ptrCast(it.entities);
        dst.count = @intCast(it.count);
        const cols = out_columns + seg * rq.term_count;
        for (0..rq.term_count) |t|
            cols[t] = if (rq.elem_sizes[t] != 0) c.ecs_field_w_size(&it, rq.elem_sizes[t], @intCast(t)) else null;
        dst.columns = cols;
        dst.column_count = @intCast(rq.term_count);
        const matched = out_matched + seg * rq.term_count;
        for (0..rq.term_count) |t| matched[t] = if (c.ecs_id_is_wildcard(idOf(s, rq.terms[t].component))) (cidFor(s, it.ids[t]) catch rq.terms[t].component) else rq.terms[t].component;
        dst.matched = matched;
        dst.changed = rq.track_changes and c.ecs_iter_changed(&it);
        seg += 1;
    }
    const rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;
    out_count.* = seg;
    return R.ok;
}

/// Slot `singleton_add`. Attaches the component to the disabled singleton entity, as `component_add`
/// attaches it to an entity.
fn singletonAdd(self_in: ?*abi_ecs.c.ke_ecs, component: abi_asset_resolver.c.ke_component_id, out_data: ?*?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const out = out_data orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or component == 0) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    if (!isRegistered(s, component)) {
        log.warn("no component has id {d}", .{component});
        return R.code(error.InvalidArgument);
    }
    begin();
    return attachTo(s, s.singletons, component, out);
}

/// Slot `singleton_get`. The bytes of the component on the singleton entity, otherwise null.
fn singletonGet(self_in: ?*abi_ecs.c.ke_ecs, component: abi_asset_resolver.c.ke_component_id) callconv(.c) ?*anyopaque {
    const self = self_in orelse return null;
    if (self.handle == null or component == 0) return null;
    const s = stateOf(self);
    const id = idOf(s, component);
    if (id == 0 or !c.ecs_has_id(s.world, s.singletons, id)) return null;
    return @constCast(c.ecs_get_id(s.world, s.singletons, id));
}

/// Slot `singleton_remove`. Removes the component from the singleton entity.
fn singletonRemove(self_in: ?*abi_ecs.c.ke_ecs, component: abi_asset_resolver.c.ke_component_id) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or component == 0) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    begin();
    const id = idOf(s, component);
    if (id != 0) c.ecs_remove_id(s.world, s.singletons, id);
    return outcome();
}

/// The handle's `destroy`. Finalizes every cached and registered query and frees their arrays, the
/// layout registry and the bitmap, then finalizes the world and frees the state last. After it
/// returns, the handle and every pointer reached through it are invalid.
fn destroy(self_in: ?*abi_ecs.c.ke_ecs) callconv(.c) void {
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
            freeRegistered(&rqs[i]);
        }
        heap.gpa.free(rqs[0..s.rquery_capacity]);
    }
    if (s.layouts) |ls| {
        for (ls[0..s.layout_count]) |l| freeFields(@constCast(l.fields[0..l.field_count]));
        heap.gpa.free(ls[0..s.layout_capacity]);
    }
    if (s.materialized) |m| heap.gpa.free(m);
    if (s.world) |w| _ = c.ecs_fini(w);
    for (s.trackers.items) |t| {
        t.lost.deinit(heap.gpa);
        heap.gpa.destroy(t);
    }
    s.trackers.deinit(heap.gpa);
    s.ids.deinit(heap.gpa);
    s.cids.deinit(heap.gpa);

    heap.gpa.destroy(s);
}

/// The factory the plugin exports. A null config takes the header's defaults. A failure after the world exists finalizes it and frees the state,
/// leaving the handle zeroed.

/// Slot `pair`. A pair id is flecs's own pair of the relation's component entity and the target, or
/// flecs's wildcard for KE_ENTITY_WILDCARD.
fn pair(self_in: ?*abi_ecs.c.ke_ecs, relation: abi_asset_resolver.c.ke_component_id, target: abi_asset_resolver.c.ke_entity, out_cid: ?*abi_asset_resolver.c.ke_component_id) callconv(.c) abi_result.c.ke_result {
    const out = out_cid orelse return R.code(error.InvalidArgument);
    out.* = 0;
    const s = stateOf(self_in orelse return R.code(error.InvalidArgument));
    const rel = idOf(s, relation);
    if (rel == 0 or c.ecs_id_is_pair(rel) or target == 0) {
        log.warn("a pair needs a registered relation and a target, given {d} and {d}", .{ relation, target });
        return R.code(error.InvalidArgument);
    }
    const second: c.ecs_entity_t = if (target == abi_ecs.c.KE_ENTITY_WILDCARD) c.EcsWildcard else @intCast(target);
    out.* = cidFor(s, c.ecs_make_pair(rel, second)) catch return R.code(error.OutOfMemory);
    return R.ok;
}

/// Slot `pair_parts`.
fn pairParts(self_in: ?*abi_ecs.c.ke_ecs, cid: abi_asset_resolver.c.ke_component_id, out_relation: ?*abi_asset_resolver.c.ke_component_id, out_target: ?*abi_asset_resolver.c.ke_entity) callconv(.c) bool {
    const s = stateOf(self_in orelse return false);
    const id = idOf(s, cid);
    if (id == 0 or !c.ecs_id_is_pair(id)) return false;
    const relation = s.cids.get(pairFirst(id)) orelse return false;
    const second = pairSecond(id);
    if (out_relation) |r| r.* = relation;
    if (out_target) |t| t.* = if (second == c.EcsWildcard) abi_ecs.c.KE_ENTITY_WILDCARD else second;
    return true;
}

fn onRemove(it: [*c]c.ecs_iter_t) callconv(.c) void {
    const t: *Tracker = @ptrCast(@alignCast(it.*.ctx));
    for (0..@intCast(it.*.count)) |i| {
        const e = it.*.entities[i];
        if (e == t.singletons) continue;
        t.lost.append(heap.gpa, @intCast(e)) catch log.warn("an entity that lost component {d} was not remembered: out of memory", .{t.cid});
    }
}

fn observe(s: *State, t: *Tracker) error{InvalidArgument}!void {
    var desc: c.ecs_observer_desc_t = std.mem.zeroes(c.ecs_observer_desc_t);
    desc.query.terms[0].id = idOf(s, t.cid);
    desc.events[0] = c.EcsOnRemove;
    desc.callback = onRemove;
    desc.ctx = t;
    begin();
    t.observer = c.ecs_observer_init(s.world, &desc);
    if (outcome() != abi_result.c.KE_OK or t.observer == 0) return error.InvalidArgument;
}

/// Slot `removal_track`. The tracker id is its index plus one.
fn removalTrack(self_in: ?*abi_ecs.c.ke_ecs, component: abi_asset_resolver.c.ke_component_id, out_tracker: ?*abi_ecs.c.ke_removal_tracker) callconv(.c) abi_result.c.ke_result {
    const out = out_tracker orelse return R.code(error.InvalidArgument);
    out.* = 0;
    const s = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (idOf(s, component) == 0) {
        log.warn("no component has id {d}", .{component});
        return R.code(error.InvalidArgument);
    }
    const t = heap.gpa.create(Tracker) catch return R.code(error.OutOfMemory);
    t.* = .{ .cid = component, .singletons = s.singletons };
    s.trackers.append(heap.gpa, t) catch {
        heap.gpa.destroy(t);
        return R.code(error.OutOfMemory);
    };
    observe(s, t) catch return R.code(error.InvalidArgument);
    out.* = s.trackers.items.len;
    return R.ok;
}

/// Slot `removals`.
fn removals(self_in: ?*abi_ecs.c.ke_ecs, tracker: abi_ecs.c.ke_removal_tracker, out_entities: [*c]abi_asset_resolver.c.ke_entity, capacity: usize, out_count: ?*usize) callconv(.c) abi_result.c.ke_result {
    const count = out_count orelse return R.code(error.InvalidArgument);
    count.* = 0;
    const s = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (tracker == 0 or tracker > s.trackers.items.len or (out_entities == null and capacity != 0)) return R.code(error.InvalidArgument);
    const t = s.trackers.items[tracker - 1];
    const n = @min(capacity, t.lost.items.len);
    for (0..n) |i| out_entities[i] = t.lost.items[i];
    count.* = t.lost.items.len;
    t.lost.replaceRangeAssumeCapacity(0, n, &.{});
    return R.ok;
}

/// Slot `entity_components`. Pairs of a registered relation get their component id on first sight;
/// flecs's own ids are left out.
fn entityComponents(self_in: ?*abi_ecs.c.ke_ecs, entity: abi_asset_resolver.c.ke_entity, out_cids: [*c]abi_asset_resolver.c.ke_component_id, capacity: usize, out_count: ?*usize) callconv(.c) abi_result.c.ke_result {
    const count = out_count orelse return R.code(error.InvalidArgument);
    count.* = 0;
    const s = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (entity == 0 or (out_cids == null and capacity != 0) or !c.ecs_is_alive(s.world, @intCast(entity))) return R.code(error.InvalidArgument);
    const type_ = c.ecs_get_type(s.world, @intCast(entity)) orelse return R.ok;
    var n: usize = 0;
    for (type_.*.array[0..@intCast(type_.*.count)]) |id| {
        const cid = s.cids.get(id) orelse blk: {
            if (!c.ecs_id_is_pair(id) or !s.cids.contains(pairFirst(id))) continue;
            break :blk cidFor(s, id) catch return R.code(error.OutOfMemory);
        };
        if (n < capacity) out_cids[n] = cid;
        n += 1;
    }
    count.* = n;
    return R.ok;
}

/// Slot `components`: every component id that is not a pair.
fn components(self_in: ?*abi_ecs.c.ke_ecs, out_cids: [*c]abi_asset_resolver.c.ke_component_id, capacity: usize, out_count: ?*usize) callconv(.c) abi_result.c.ke_result {
    const count = out_count orelse return R.code(error.InvalidArgument);
    count.* = 0;
    const s = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (out_cids == null and capacity != 0) return R.code(error.InvalidArgument);
    var n: usize = 0;
    for (s.ids.items, 1..) |id, cid| {
        if (c.ecs_id_is_pair(id)) continue;
        if (n < capacity) out_cids[n] = @intCast(cid);
        n += 1;
    }
    count.* = n;
    return R.ok;
}

/// The values of one component a snapshot holds: its holders and their bytes, and the singleton's.
const Column = struct {
    cid: abi_asset_resolver.c.ke_component_id,
    size: usize,
    holders: []abi_asset_resolver.c.ke_entity,
    bytes: []u8,
    singleton: ?[]u8,
};

/// What `snapshot` captured: the world it came from, the id counters, the reserve bitmap, the
/// living entities and one column per listed component.
const Snapshot = struct {
    state: *State,
    next_user: u32,
    reserve_next: u32,
    materialized: ?[]u8,
    alive: []abi_asset_resolver.c.ke_entity,
    columns: []Column,
};

fn freeSnapshot(snap: *Snapshot) void {
    for (snap.columns) |col| {
        heap.gpa.free(col.holders);
        heap.gpa.free(col.bytes);
        if (col.singleton) |b| heap.gpa.free(b);
    }
    heap.gpa.free(snap.columns);
    heap.gpa.free(snap.alive);
    if (snap.materialized) |m| heap.gpa.free(m);
    heap.gpa.destroy(snap);
}

fn livingEntities(s: *State) error{OutOfMemory}![]abi_asset_resolver.c.ke_entity {
    var list: std.ArrayListUnmanaged(abi_asset_resolver.c.ke_entity) = .empty;
    errdefer list.deinit(heap.gpa);
    const reserved = @min(s.reserve_next.load(.monotonic), s.reserve_end - s.reserve_low);
    for (s.reserve_low..s.reserve_low + reserved) |e| if (c.ecs_is_alive(s.world, e)) try list.append(heap.gpa, e);
    for (s.user_start..s.next_user) |e| if (c.ecs_is_alive(s.world, e)) try list.append(heap.gpa, e);
    return list.toOwnedSlice(heap.gpa);
}

fn capture(s: *State, cid: abi_asset_resolver.c.ke_component_id) error{ OutOfMemory, InvalidArgument }!Column {
    const id = idOf(s, cid);
    if (id == 0) return error.InvalidArgument;
    const ti = c.ecs_get_type_info(s.world, id);
    const size: usize = if (ti != null) @intCast(ti.*.size) else 0;
    var holders: std.ArrayListUnmanaged(abi_asset_resolver.c.ke_entity) = .empty;
    errdefer holders.deinit(heap.gpa);
    var bytes: std.ArrayListUnmanaged(u8) = .empty;
    errdefer bytes.deinit(heap.gpa);
    var desc: c.ecs_query_desc_t = std.mem.zeroes(c.ecs_query_desc_t);
    desc.terms[0].id = id;
    const q = c.ecs_query_init(s.world, &desc) orelse return error.InvalidArgument;
    defer c.ecs_query_fini(q);
    var it = c.ecs_query_iter(s.world, q);
    while (c.ecs_query_next(&it)) {
        const n: usize = @intCast(it.count);
        for (it.entities[0..n]) |e| try holders.append(heap.gpa, @intCast(e));
        if (size != 0) {
            const col: [*]const u8 = @ptrCast(c.ecs_field_w_size(&it, size, 0));
            try bytes.appendSlice(heap.gpa, col[0 .. n * size]);
        }
    }
    var singleton: ?[]u8 = null;
    if (size != 0 and c.ecs_has_id(s.world, s.singletons, id)) {
        const src: [*]const u8 = @ptrCast(c.ecs_get_id(s.world, s.singletons, id));
        singleton = try heap.gpa.dupe(u8, src[0..size]);
    } else if (size == 0 and c.ecs_has_id(s.world, s.singletons, id)) singleton = try heap.gpa.alloc(u8, 0);
    errdefer if (singleton) |b| heap.gpa.free(b);
    const h = try holders.toOwnedSlice(heap.gpa);
    errdefer heap.gpa.free(h);
    return .{ .cid = cid, .size = size, .holders = h, .bytes = try bytes.toOwnedSlice(heap.gpa), .singleton = singleton };
}

/// Slot `snapshot`.
fn snapshot(self_in: ?*abi_ecs.c.ke_ecs, listed: [*c]const abi_asset_resolver.c.ke_component_id, listed_count: u32, out_snapshot: ?*?*abi_ecs.c.ke_ecs_snapshot) callconv(.c) abi_result.c.ke_result {
    const out = out_snapshot orelse return R.code(error.InvalidArgument);
    out.* = null;
    const s = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (listed == null and listed_count != 0) return R.code(error.InvalidArgument);
    const snap = heap.gpa.create(Snapshot) catch return R.code(error.OutOfMemory);
    snap.* = .{ .state = s, .next_user = s.next_user, .reserve_next = s.reserve_next.load(.monotonic), .materialized = null, .alive = &.{}, .columns = &.{} };
    fill(s, snap, if (listed_count == 0) &.{} else listed[0..listed_count]) catch |err| {
        freeSnapshot(snap);
        if (err == error.InvalidArgument) log.warn("a snapshot lists a component that is not registered", .{});
        return R.code(err);
    };
    out.* = @ptrCast(snap);
    return R.ok;
}

fn fill(s: *State, snap: *Snapshot, listed: []const abi_asset_resolver.c.ke_component_id) error{ OutOfMemory, InvalidArgument }!void {
    if (s.materialized) |m| snap.materialized = try heap.gpa.dupe(u8, m);
    snap.alive = try livingEntities(s);
    const columns = try heap.gpa.alloc(Column, listed.len);
    var filled: usize = 0;
    errdefer {
        for (columns[0..filled]) |col| {
            heap.gpa.free(col.holders);
            heap.gpa.free(col.bytes);
            if (col.singleton) |b| heap.gpa.free(b);
        }
        heap.gpa.free(columns);
    }
    for (listed, columns) |cid, *col| {
        col.* = try capture(s, cid);
        filled += 1;
    }
    snap.columns = columns;
}

fn contains(sorted: []const abi_asset_resolver.c.ke_entity, e: abi_asset_resolver.c.ke_entity) bool {
    return std.sort.binarySearch(abi_asset_resolver.c.ke_entity, sorted, e, struct {
        fn order(key: abi_asset_resolver.c.ke_entity, item: abi_asset_resolver.c.ke_entity) std.math.Order {
            return std.math.order(key, item);
        }
    }.order) != null;
}

/// Slot `restore`. Entities alive now and not then are deleted, entities alive then are made alive
/// with their ids, and every listed component is taken from those that did not hold it and given
/// back, with its bytes, to those that did; then the id counters and the reserve bitmap return.
fn restore(self_in: ?*abi_ecs.c.ke_ecs, snap_in: ?*const abi_ecs.c.ke_ecs_snapshot) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self_in orelse return R.code(error.InvalidArgument));
    const snap: *const Snapshot = @ptrCast(@alignCast(snap_in orelse return R.code(error.InvalidArgument)));
    if (snap.state != s) {
        log.warn("restoring a snapshot of another world", .{});
        return R.code(error.InvalidArgument);
    }
    const now = livingEntities(s) catch return R.code(error.OutOfMemory);
    defer heap.gpa.free(now);
    begin();
    for (now) |e| if (!contains(snap.alive, e)) c.ecs_delete(s.world, e);
    for (snap.alive) |e| if (!c.ecs_is_alive(s.world, e)) {
        if (e >= s.user_start) makeUserAlive(s, e) else _ = c.ecs_make_alive(s.world, e);
    };
    for (snap.columns) |col| {
        const id = idOf(s, col.cid);
        const current = capture(s, col.cid) catch |err| return R.code(err);
        defer {
            heap.gpa.free(current.holders);
            heap.gpa.free(current.bytes);
            if (current.singleton) |b| heap.gpa.free(b);
        }
        var held: std.AutoHashMapUnmanaged(abi_asset_resolver.c.ke_entity, void) = .empty;
        defer held.deinit(heap.gpa);
        for (col.holders) |e| held.put(heap.gpa, e, {}) catch return R.code(error.OutOfMemory);
        for (current.holders) |e| if (!held.contains(e) and c.ecs_is_alive(s.world, e)) c.ecs_remove_id(s.world, e, id);
        for (col.holders, 0..) |e, i| {
            c.ecs_add_id(s.world, e, id);
            if (col.size != 0) {
                const dst: [*]u8 = @ptrCast(c.ecs_get_mut_id(s.world, e, id));
                @memcpy(dst[0..col.size], col.bytes[i * col.size ..][0..col.size]);
                c.ecs_modified_id(s.world, e, id);
            }
        }
        if (col.singleton) |b| {
            c.ecs_add_id(s.world, s.singletons, id);
            if (col.size != 0) {
                const dst: [*]u8 = @ptrCast(c.ecs_get_mut_id(s.world, s.singletons, id));
                @memcpy(dst[0..col.size], b);
            }
        } else c.ecs_remove_id(s.world, s.singletons, id);
    }
    s.next_user = snap.next_user;
    s.reserve_next.store(snap.reserve_next, .monotonic);
    if (snap.materialized) |m| {
        if (s.materialized) |cur| @memcpy(cur, m);
    } else if (s.materialized) |cur| @memset(cur, 0);
    return outcome();
}

/// Slot `snapshot_free`.
fn snapshotFree(self_in: ?*abi_ecs.c.ke_ecs, snap_in: ?*abi_ecs.c.ke_ecs_snapshot) callconv(.c) void {
    _ = self_in;
    freeSnapshot(@ptrCast(@alignCast(snap_in orelse return)));
}

export fn ke_ecs_flecs_create(
    config: ?*const abi_ecs.c.ke_ecs_config,
    out_ecs: ?*abi_ecs.c.ke_ecs_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_ecs orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_ecs.c.ke_ecs_handle);
    out.* = create(config) catch |err| {
        log.warn("creating the ECS failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(config: ?*const abi_ecs.c.ke_ecs_config) R.Error!abi_ecs.c.ke_ecs_handle {
    const reserved_id_capacity = (config orelse {
        log.warn("creating the ECS needs its config", .{});
        return error.InvalidArgument;
    }).*.reserved_id_capacity;
    if (reserved_id_capacity == 0) {
        log.warn("creating the ECS needs a world id base above 0, the capacity of entity_reserve", .{});
        return error.InvalidArgument;
    }

    installFlecsOsApi();

    const s = heap.gpa.create(State) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(s);
    s.* = .{
        .api = std.mem.zeroes(abi_ecs.c.ke_ecs),
        .world = null,
        .singletons = 0,
        .reserve_low = 0,
        .reserve_end = reserved_id_capacity,
        .reserve_next = std.atomic.Value(u32).init(0),
        .materialized = null,
        .queries = null,
        .query_count = 0,
        .query_capacity = 0,
        .rqueries = null,
        .rquery_count = 0,
        .rquery_capacity = 0,
        .layouts = null,
        .layout_count = 0,
        .layout_capacity = 0,
    };

    s.world = c.ecs_init();
    if (s.world == null) return error.NotInitialized;
    errdefer _ = c.ecs_fini(s.world);

    s.reserve_low = @intCast(c.ecs_get_max_id(s.world) + 1);
    if (reserved_id_capacity <= s.reserve_low) {
        log.warn("reserved_id_capacity {d} leaves no room below it for the reserve pool", .{reserved_id_capacity});
        return error.InvalidArgument;
    }
    s.next_user = user_id_start;
    s.user_start = user_id_start;
    if (reserved_id_capacity >= user_id_start) {
        log.warn("reserved_id_capacity {d} leaves no room below {d} for flecs's own entities", .{ reserved_id_capacity, user_id_start });
        return error.InvalidArgument;
    }
    if (c.ecs_entity_range_new(s.world, reserved_id_capacity, user_id_start - 1)) |range| {
        s.own_range = range;
        s.user_range = c.ecs_entity_range_new(s.world, user_id_start, 0) orelse {
            log.warn("flecs would not keep its ids clear of the created entities", .{});
            return error.NotInitialized;
        };
        c.ecs_entity_range_set(s.world, range);
    } else {
        log.warn("flecs would not keep its ids clear of the reserve pool", .{});
        return error.NotInitialized;
    }
    s.singletons = c.ecs_new(s.world);
    c.ecs_enable(s.world, s.singletons, false);

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
    s.api.component_field_write = componentFieldWrite;
    s.api.query_register = queryRegister;
    s.api.query_resolve = queryResolve;
    s.api.singleton_add = singletonAdd;
    s.api.singleton_get = singletonGet;
    s.api.singleton_remove = singletonRemove;
    s.api.pair = pair;
    s.api.pair_parts = pairParts;
    s.api.removal_track = removalTrack;
    s.api.removals = removals;
    s.api.entity_components = entityComponents;
    s.api.components = components;
    s.api.snapshot = snapshot;
    s.api.restore = restore;
    s.api.snapshot_free = snapshotFree;

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;

test {
    _ = field_write;
}

fn made() !abi_ecs.c.ke_ecs_handle {
    var h: abi_ecs.c.ke_ecs_handle = undefined;
    try R.check(ke_ecs_flecs_create(&test_config, &h));
    return h;
}

fn register(h: abi_ecs.c.ke_ecs_handle, params: *const abi_ecs.c.ke_component_params) R.Error!abi_asset_resolver.c.ke_component_id {
    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(h.ref.?.component_register.?(h.ref, params, &cid));
    return cid;
}

fn spawn(h: abi_ecs.c.ke_ecs_handle) R.Error!abi_asset_resolver.c.ke_entity {
    var entity: abi_asset_resolver.c.ke_entity = 0;
    try R.check(h.ref.?.entity_create.?(h.ref, &entity));
    return entity;
}

fn reserve(h: abi_ecs.c.ke_ecs_handle) R.Error!abi_asset_resolver.c.ke_entity {
    var entity: abi_asset_resolver.c.ke_entity = 0;
    try R.check(h.ref.?.entity_reserve.?(h.ref, &entity));
    return entity;
}

fn attach(h: abi_ecs.c.ke_ecs_handle, entity: abi_asset_resolver.c.ke_entity, cid: abi_asset_resolver.c.ke_component_id) R.Error!?*anyopaque {
    var data: ?*anyopaque = null;
    try R.check(h.ref.?.component_add.?(h.ref, entity, cid, &data));
    return data;
}

fn queryOf(h: abi_ecs.c.ke_ecs_handle, cids: []const abi_asset_resolver.c.ke_component_id) R.Error!abi_ecs.c.ke_query_id {
    var terms: [32]abi_ecs.c.ke_ecs_query_term = undefined;
    for (cids, terms[0..cids.len]) |cid, *t| t.* = .{ .component = cid, .access = abi_ecs.c.KE_ECS_ACCESS_READ };
    return registerDesc(h, .{ .terms = &terms, .term_count = @intCast(cids.len), .with = null, .with_count = 0, .without = null, .without_count = 0, .track_changes = false });
}

fn registerDesc(h: abi_ecs.c.ke_ecs_handle, desc: abi_ecs.c.ke_ecs_query_desc) R.Error!abi_ecs.c.ke_query_id {
    var query: abi_ecs.c.ke_query_id = abi_ecs.c.KE_QUERY_INVALID;
    try R.check(h.ref.?.query_register.?(h.ref, &desc, &query));
    return query;
}

fn sized(h: abi_ecs.c.ke_ecs_handle, name: [*:0]const u8) R.Error!abi_asset_resolver.c.ke_component_id {
    return register(h, &abi_ecs.c.ke_component_params{ .name = name, .size = 4, .alignment = 4, .fields = null, .field_count = 0 });
}

fn term(cid: abi_asset_resolver.c.ke_component_id, access: c_uint) abi_ecs.c.ke_ecs_query_term {
    return .{ .component = cid, .access = @intCast(access) };
}

fn tracking(h: abi_ecs.c.ke_ecs_handle, terms: []const abi_ecs.c.ke_ecs_query_term) R.Error!abi_ecs.c.ke_query_id {
    return registerDesc(h, .{ .terms = terms.ptr, .term_count = @intCast(terms.len), .with = null, .with_count = 0, .without = null, .without_count = 0, .track_changes = true });
}

const Resolved = struct {
    segs: [4]abi_ecs.c.ke_ecs_segment = undefined,
    columns: [16]?*anyopaque = undefined,
    matched: [16]abi_asset_resolver.c.ke_component_id = undefined,
    count: usize = 0,

    fn changedCount(r: *const Resolved) usize {
        var n: usize = 0;
        for (r.segs[0..@min(r.count, r.segs.len)]) |seg| n += @intFromBool(seg.changed);
        return n;
    }
};

fn resolveInto(h: abi_ecs.c.ke_ecs_handle, query: abi_ecs.c.ke_query_id, capacity: usize) R.Error!Resolved {
    var r: Resolved = .{};
    try R.check(h.ref.?.query_resolve.?(h.ref, query, &r.segs, capacity, &r.columns[0], &r.matched[0], &r.count));
    return r;
}

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
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    const first = try register(handle, &abi_ecs.c.ke_component_params{ .name = "dup_name", .size = 8, .alignment = 4, .fields = null, .field_count = 0 });
    try testing.expect(first != 0);

    try testing.expectError(error.InvalidArgument, register(handle, &abi_ecs.c.ke_component_params{ .name = "dup_name", .size = 16, .alignment = 4, .fields = null, .field_count = 0 }));
}

test "a component keeps the alignment it was registered with, and a lookup reports it" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(handle.ref.?.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "aligned4", .size = 12, .alignment = 4, .fields = null, .field_count = 0 }, &cid));
    try testing.expect(cid != 0);
    var meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    try testing.expect(handle.ref.?.component_lookup.?(handle.ref, "aligned4", &meta));
    try testing.expectEqual(@as(usize, 4), meta.alignment);
}

test "a tag registered with size zero is found by lookup with size zero" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(handle.ref.?.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "node.paddle", .size = 0, .alignment = 0, .fields = null, .field_count = 0 }, &cid));
    var meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    try testing.expect(handle.ref.?.component_lookup.?(handle.ref, "node.paddle", &meta));
    try testing.expectEqual(cid, meta.cid);
    try testing.expectEqual(@as(usize, 0), meta.size);
}

test "an entity that was never registered as a component is not found by lookup" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(handle.ref.?.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "scope.inner", .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, &cid));
    try testing.expect(!handle.ref.?.component_lookup.?(handle.ref, "scope", null));
}

test "a sized component with an alignment of zero is refused, not given a default" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    var ignored: abi_asset_resolver.c.ke_component_id = 0;
    try testing.expectError(error.InvalidArgument, R.check(handle.ref.?.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "unaligned", .size = 12, .alignment = 0, .fields = null, .field_count = 0 }, &ignored)));
}

test "componentRegister rejects re-registering a name with a different alignment" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    _ = try register(handle, &abi_ecs.c.ke_component_params{ .name = "realigned", .size = 16, .alignment = 4, .fields = null, .field_count = 0 });
    try testing.expectError(error.InvalidArgument, register(handle, &abi_ecs.c.ke_component_params{ .name = "realigned", .size = 16, .alignment = 16, .fields = null, .field_count = 0 }));
}

test "componentRegister refuses an alignment that is not a power of two" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    try testing.expectError(error.InvalidArgument, register(handle, &abi_ecs.c.ke_component_params{ .name = "odd_align", .size = 12, .alignment = 3, .fields = null, .field_count = 0 }));
}

fn field(name: [*c]const u8, t: abi_ecs_variant.c.ke_variant_type, offset: u32, size: u32) abi_ecs.c.ke_component_field {
    return .{
        .name = name,
        .type = t,
        .offset = offset,
        .size = size,
        .default_value = std.mem.zeroes(abi_ecs_variant.c.ke_variant),
    };
}

const swapped_a = [_]abi_ecs.c.ke_component_field{
    field("layers", abi_ecs_variant.c.KE_VARIANT_INT, 0, 4),
    field("ior", abi_ecs_variant.c.KE_VARIANT_FLOAT, 4, 4),
};
const swapped_b = [_]abi_ecs.c.ke_component_field{
    field("ior", abi_ecs_variant.c.KE_VARIANT_FLOAT, 0, 4),
    field("layers", abi_ecs_variant.c.KE_VARIANT_INT, 4, 4),
};

test "two layouts of the same size disagree at the first field that moved" {
    try testing.expectEqual(@as(?usize, 0), firstLayoutDiff(&swapped_a, &swapped_b));
    try testing.expectEqual(@as(?usize, null), firstLayoutDiff(&swapped_a, &swapped_a));
}

test "a field that kept its place but changed meaning still counts as a difference" {
    const as_float = [_]abi_ecs.c.ke_component_field{field("value", abi_ecs_variant.c.KE_VARIANT_FLOAT, 0, 4)};
    const as_int = [_]abi_ecs.c.ke_component_field{field("value", abi_ecs_variant.c.KE_VARIANT_INT, 0, 4)};
    try testing.expectEqual(@as(?usize, 0), firstLayoutDiff(&as_float, &as_int));
}

test "a layout that ran out of fields disagrees at the first one the other still has" {
    const shorter = [_]abi_ecs.c.ke_component_field{field("ior", abi_ecs_variant.c.KE_VARIANT_FLOAT, 0, 4)};
    try testing.expectEqual(@as(?usize, 1), firstLayoutDiff(&shorter, &swapped_b));
    try testing.expectEqual(@as(?usize, 1), firstLayoutDiff(&swapped_b, &shorter));
}

test "a table reaching past the component's size belongs to another type" {
    try testing.expect(layoutFitsSize(&swapped_a, 8));
    try testing.expect(!layoutFitsSize(&swapped_a, 7));
    try testing.expect(layoutFitsSize(&swapped_a, 16));
}

test "componentRegister migrates a second layout the size check cannot tell apart, keeping the id" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    const first = try register(handle, &abi_ecs.c.ke_component_params{ .name = "swapped", .size = 8, .alignment = 4, .fields = &swapped_a, .field_count = swapped_a.len });
    try testing.expect(first != 0);

    try testing.expectEqual(first, try register(handle, &abi_ecs.c.ke_component_params{ .name = "swapped", .size = 8, .alignment = 4, .fields = &swapped_b, .field_count = swapped_b.len }));
}

test "componentRegister accepts a second registration describing the same layout" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    const first = try register(handle, &abi_ecs.c.ke_component_params{ .name = "agreed", .size = 8, .alignment = 4, .fields = &swapped_a, .field_count = swapped_a.len });
    const second = try register(handle, &abi_ecs.c.ke_component_params{ .name = "agreed", .size = 8, .alignment = 4, .fields = &swapped_a, .field_count = swapped_a.len });
    try testing.expectEqual(first, second);
}

test "a registrant with no table still joins one that has one, on size alone" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    const described = try register(handle, &abi_ecs.c.ke_component_params{ .name = "partial", .size = 8, .alignment = 4, .fields = &swapped_a, .field_count = swapped_a.len });
    const tableless = try register(handle, &abi_ecs.c.ke_component_params{ .name = "partial", .size = 8, .alignment = 4, .fields = null, .field_count = 0 });
    try testing.expectEqual(described, tableless);
}

test "the table of the first registrant to carry one describes the component afterwards" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    var tableless: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(handle.ref.?.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "late_table", .size = 8, .alignment = 4, .fields = null, .field_count = 0 }, &tableless));
    {
        var ignored: abi_asset_resolver.c.ke_component_id = 0;
        try R.check(handle.ref.?.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "late_table", .size = 8, .alignment = 4, .fields = &swapped_a, .field_count = swapped_a.len }, &ignored));
    }

    var meta: abi_ecs.c.ke_component_meta = undefined;
    try testing.expect(handle.ref.?.component_lookup.?(handle.ref, "late_table", &meta));
    try testing.expectEqual(tableless, meta.cid);
    try testing.expectEqual(@as(u32, swapped_a.len), meta.field_count);
    try testing.expect(meta.fields != null);
}

test "a field table is copied, names and enum names with it, so the caller's may go after the call" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    var name_buf = "speed".*;
    var choice_buf = "fast".*;
    var choices = [_]?[*:0]const u8{&choice_buf};
    var fields = [_]abi_ecs.c.ke_component_field{.{ .name = &name_buf, .type = abi_ecs_variant.c.KE_VARIANT_INT, .offset = 0, .size = 4, .enum_names = @ptrCast(&choices), .enum_count = 1 }};
    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(handle.ref.?.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "copied_table", .size = 4, .alignment = 4, .fields = &fields, .field_count = 1 }, &cid));
    @memset(&name_buf, 'x');
    @memset(&choice_buf, 'x');
    fields[0].offset = 99;

    var meta: abi_ecs.c.ke_component_meta = undefined;
    try testing.expect(handle.ref.?.component_lookup.?(handle.ref, "copied_table", &meta));
    try testing.expectEqualStrings("speed", std.mem.span(meta.fields.?[0].name.?));
    try testing.expectEqual(@as(u32, 0), meta.fields.?[0].offset);
    const names: [*]const ?[*:0]const u8 = @ptrCast(meta.fields.?[0].enum_names);
    try testing.expectEqualStrings("fast", std.mem.span(names[0].?));
}

test "a field with no enum names is copied without a list, whatever pointer came with the count of zero" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    var none = [_]?[*:0]const u8{null};
    const fields = [_]abi_ecs.c.ke_component_field{.{ .name = "name", .type = abi_ecs_variant.c.KE_VARIANT_STRING, .offset = 0, .size = 4, .enum_names = @ptrCast(&none), .enum_count = 0 }};
    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(handle.ref.?.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "no_enum", .size = 4, .alignment = 4, .fields = &fields, .field_count = 1 }, &cid));
    var meta: abi_ecs.c.ke_component_meta = undefined;
    try testing.expect(handle.ref.?.component_lookup.?(handle.ref, "no_enum", &meta));
    try testing.expect(meta.fields.?[0].enum_names == null);
}

test "componentRegister refuses a table describing bytes the component does not have" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    try testing.expectError(error.InvalidArgument, register(handle, &abi_ecs.c.ke_component_params{ .name = "too_small", .size = 4, .alignment = 4, .fields = &swapped_a, .field_count = swapped_a.len }));
}

test "componentRegister is idempotent for a repeated identical size" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    const first = try register(handle, &abi_ecs.c.ke_component_params{ .name = "same_name", .size = 12, .alignment = 4, .fields = null, .field_count = 0 });
    const second = try register(handle, &abi_ecs.c.ke_component_params{ .name = "same_name", .size = 12, .alignment = 4, .fields = null, .field_count = 0 });
    try testing.expectEqual(first, second);
}

/// Runs the abort hook as flecs does on an internal failure, after flecs reported `msg`.
pub fn debugRunAbortHook(msg: [*:0]const u8) void {
    installFlecsOsApi();
    flecsLogHandler(-4, "flecs_probe.c", 7, msg);
    c.ecs_os_get_api().abort_.?();
}

test "a check flecs fails is answered as an invalid argument instead of an abort" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const tag = try register(handle, &abi_ecs.c.ke_component_params{ .name = "refusal_tag", .size = 0, .alignment = 0, .fields = null, .field_count = 0 });
    const entity = try spawn(handle);
    _ = try attach(handle, entity, tag);

    begin();
    c.ecs_add_id(stateOf(handle.ref.?).world, @intCast(entity), 0);
    try testing.expectError(error.InvalidArgument, R.check(outcome()));
    try testing.expect(!flecs_refused);
}

test "a refusal does not leak into the next call on the same thread" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const entity = try spawn(handle);

    var data: ?*anyopaque = null;
    _ = handle.ref.?.component_add.?(handle.ref, entity, 0x7fff_fff0, &data);
    flecsLogHandler(-4, "elsewhere.c", 1, "a message nobody answered for");
    _ = try spawn(handle);
}

test "a reserved id can never be one the world's own allocator will issue" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    const reserved = try reserve(handle);
    try testing.expect(reserved != 0);
    try testing.expect(reserved < test_config.reserved_id_capacity);

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const created = try spawn(handle);
        try testing.expect(created >= test_config.reserved_id_capacity);
    }
}

test "reserving past the pool's capacity reports exhaustion instead of colliding" {
    var config = test_config;
    var probe: abi_ecs.c.ke_ecs_handle = undefined;
    try R.check(ke_ecs_flecs_create(&config, &probe));
    const low = stateOf(probe.ref.?).reserve_low;
    probe.destroy.?(probe.ref);

    config.reserved_id_capacity = low + 4;
    var handle: abi_ecs.c.ke_ecs_handle = undefined;
    try R.check(ke_ecs_flecs_create(&config, &handle));
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var i: usize = 0;
    while (i < 4) : (i += 1) try testing.expect(try reserve(handle) != 0);
    var spent: abi_asset_resolver.c.ke_entity = 1;
    try testing.expectError(error.OutOfMemory, R.check(e.entity_reserve.?(handle.ref, &spent)));
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_entity, 0), spent);
}

test "every reserved id is distinct" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    var seen: [256]abi_asset_resolver.c.ke_entity = undefined;
    for (&seen) |*slot| slot.* = try reserve(handle);
    for (seen, 0..) |a, i| {
        try testing.expect(a != 0);
        for (seen[i + 1 ..]) |b| try testing.expect(a != b);
    }
}

test "reserving concurrently never hands the same id to two threads" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    const thread_count = 8;
    const per_thread = 2000;
    var ids: [thread_count][per_thread]abi_asset_resolver.c.ke_entity = undefined;

    const Worker = struct {
        fn run(ecs: *abi_ecs.c.ke_ecs, out: *[per_thread]abi_asset_resolver.c.ke_entity) void {
            for (out) |*slot| {
                if (ecs.entity_reserve.?(ecs, slot) != abi_result.c.KE_OK) slot.* = 0;
            }
        }
    };

    var threads: [thread_count]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, Worker.run, .{ handle.ref.?, &ids[i] });
    }
    for (threads) |t| t.join();

    var flat: [thread_count * per_thread]abi_asset_resolver.c.ke_entity = undefined;
    for (ids, 0..) |row, i| @memcpy(flat[i * per_thread ..][0..per_thread], &row);
    std.mem.sort(abi_asset_resolver.c.ke_entity, &flat, {}, std.sort.asc(abi_asset_resolver.c.ke_entity));
    for (flat[1..], 0..) |v, i| {
        try testing.expect(v != 0);
        try testing.expect(v != flat[i]);
    }
}

test "a reserved id is not in the world until something materializes it" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "reserve_probe", .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, &cid));
    const reserved = try reserve(handle);
    try testing.expect(e.component_get.?(handle.ref, reserved, cid) == null);

    try R.check(e.entity_materialize.?(handle.ref, reserved));
    try testing.expect((try attach(handle, reserved, cid)) != null);
}

test "attaching to a reserved id materializes it without a separate call" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "attach_probe", .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, &cid));
    const reserved = try reserve(handle);

    const slot = (try attach(handle, reserved, cid)) orelse return error.TestUnexpectedResult;
    @as(*u32, @ptrCast(@alignCast(slot))).* = 0xabcd;
    const read = e.component_get.?(handle.ref, reserved, cid) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 0xabcd), @as(*u32, @ptrCast(@alignCast(read))).*);
}

test "materializing an id twice is a no-op rather than a second entity" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "twice_probe", .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, &cid));
    const reserved = try reserve(handle);
    try R.check(e.entity_materialize.?(handle.ref, reserved));
    const slot = (try attach(handle, reserved, cid)) orelse return error.TestUnexpectedResult;
    @as(*u32, @ptrCast(@alignCast(slot))).* = 7;

    try R.check(e.entity_materialize.?(handle.ref, reserved));
    const read = e.component_get.?(handle.ref, reserved, cid) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 7), @as(*u32, @ptrCast(@alignCast(read))).*);
}

test "materializing an id the world already owns leaves it alone" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "owned_probe", .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, &cid));
    const created = try spawn(handle);
    const slot = (try attach(handle, created, cid)) orelse return error.TestUnexpectedResult;
    @as(*u32, @ptrCast(@alignCast(slot))).* = 99;

    try R.check(e.entity_materialize.?(handle.ref, created));
    const read = e.component_get.?(handle.ref, created, cid) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 99), @as(*u32, @ptrCast(@alignCast(read))).*);
}

test "a split that leaves no room for the reserve pool is refused" {
    var config = abi_ecs.c.ke_ecs_config{ .reserved_id_capacity = 1 };
    var handle: abi_ecs.c.ke_ecs_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_ecs_flecs_create(&config, &handle)));
    try testing.expect(handle.ref == null);
}

test "a caller may move the split between the two id allocators" {
    var config = abi_ecs.c.ke_ecs_config{ .reserved_id_capacity = 1_000_000 };
    var handle: abi_ecs.c.ke_ecs_handle = undefined;
    try R.check(ke_ecs_flecs_create(&config, &handle));
    defer handle.destroy.?(handle.ref);

    try testing.expect(try reserve(handle) < 1_000_000);
    try testing.expect(try spawn(handle) >= 1_000_000);
}

test "a reserved entity that was destroyed does not come back on the next attach" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "revive_probe", .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, &cid));
    const reserved = try reserve(handle);
    try testing.expect((try attach(handle, reserved, cid)) != null);

    try R.check(e.entity_destroy.?(handle.ref, reserved));
    var revived: ?*anyopaque = null;
    try testing.expectError(error.InvalidArgument, R.check(e.component_add.?(handle.ref, reserved, cid, &revived)));
    try testing.expect(revived == null);
    try testing.expect(e.component_get.?(handle.ref, reserved, cid) == null);
}

const Layered = extern struct {
    layers: u32,
    ior: f32,
};

fn defaulted(name: [*c]const u8, t: abi_ecs_variant.c.ke_variant_type, offset: u32, size: u32, v: abi_ecs_variant.c.ke_variant) abi_ecs.c.ke_component_field {
    return .{ .name = name, .type = t, .offset = offset, .size = size, .default_value = v };
}

fn intVariant(i: i64) abi_ecs_variant.c.ke_variant {
    var v = std.mem.zeroes(abi_ecs_variant.c.ke_variant);
    v.type = abi_ecs_variant.c.KE_VARIANT_INT;
    v.unnamed_0.i = i;
    return v;
}

fn floatVariant(f: f64) abi_ecs_variant.c.ke_variant {
    var v = std.mem.zeroes(abi_ecs_variant.c.ke_variant);
    v.type = abi_ecs_variant.c.KE_VARIANT_FLOAT;
    v.unnamed_0.f = f;
    return v;
}

const layered_fields = [_]abi_ecs.c.ke_component_field{
    defaulted("layers", abi_ecs_variant.c.KE_VARIANT_INT, 0, 4, intVariant(1)),
    defaulted("ior", abi_ecs_variant.c.KE_VARIANT_FLOAT, 4, 4, floatVariant(1.5)),
};

test "attaching a component seeds the defaults its field table declares" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "layered", .size = @sizeOf(Layered), .alignment = @alignOf(Layered), .fields = &layered_fields, .field_count = layered_fields.len }, &cid));
    try testing.expect(cid != 0);

    const entity = try spawn(handle);
    const slot = (try attach(handle, entity, cid)) orelse return error.TestUnexpectedResult;
    const v: *const Layered = @ptrCast(@alignCast(slot));

    try testing.expectEqual(@as(u32, 1), v.layers);
    try testing.expectEqual(@as(f32, 1.5), v.ior);
}

test "attaching a component that is already there keeps the value it holds" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "layered_twice", .size = @sizeOf(Layered), .alignment = @alignOf(Layered), .fields = &layered_fields, .field_count = layered_fields.len }, &cid));
    const entity = try spawn(handle);

    const first: *Layered = @ptrCast(@alignCast((try attach(handle, entity, cid)).?));
    first.layers = 0b1010;

    const second: *const Layered = @ptrCast(@alignCast((try attach(handle, entity, cid)).?));
    try testing.expectEqual(@as(u32, 0b1010), second.layers);
}

test "a component registered without a field table still attaches zeroed" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "untabled", .size = @sizeOf(Layered), .alignment = @alignOf(Layered), .fields = null, .field_count = 0 }, &cid));
    const entity = try spawn(handle);
    const v: *const Layered = @ptrCast(@alignCast((try attach(handle, entity, cid)).?));

    try testing.expectEqual(@as(u32, 0), v.layers);
}

test "a component attached over memory a destroyed entity dirtied still arrives zeroed" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "recycled", .size = @sizeOf(Layered), .alignment = @alignOf(Layered), .fields = null, .field_count = 0 }, &cid));
    const first = try spawn(handle);
    const dirty: [*]u8 = @ptrCast((try attach(handle, first, cid)).?);
    @memset(dirty[0..@sizeOf(Layered)], 0xAA);
    try R.check(e.entity_destroy.?(handle.ref, first));

    const second = try spawn(handle);
    const v: *const Layered = @ptrCast(@alignCast((try attach(handle, second, cid)).?));

    try testing.expectEqual(@as(u32, 0), v.layers);
}

test "registering the same component tuple twice returns one query, and another order another" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var a: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "dedup_a", .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, &a));
    var b: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "dedup_b", .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, &b));
    const ab = [_]abi_asset_resolver.c.ke_component_id{ a, b };
    const ba = [_]abi_asset_resolver.c.ke_component_id{ b, a };

    const first = (try queryOf(handle, &ab));
    try testing.expect(first != abi_ecs.c.KE_QUERY_INVALID);
    try testing.expectEqual(first, (try queryOf(handle, &ab)));
    try testing.expect((try queryOf(handle, &ba)) != first);
}

test "resolving a query into too small an array reports every segment it matches" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var shared: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "resolve_shared", .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, &shared));
    var extras: [4]abi_asset_resolver.c.ke_component_id = undefined;
    const names = [_][*:0]const u8{ "resolve_x0", "resolve_x1", "resolve_x2", "resolve_x3" };
    for (&extras, names) |*cid, name| try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = name, .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, cid));

    for (0..16) |mask| {
        const entity = try spawn(handle);
        try testing.expect((try attach(handle, entity, shared)) != null);
        for (extras, 0..) |cid, bit| {
            if ((mask >> @intCast(bit)) & 1 != 0) try testing.expect((try attach(handle, entity, cid)) != null);
        }
    }

    const cids = [_]abi_asset_resolver.c.ke_component_id{shared};
    const query = (try queryOf(handle, &cids));
    try testing.expect(query != abi_ecs.c.KE_QUERY_INVALID);

    var small: [4]abi_ecs.c.ke_ecs_segment = undefined;
    var small_columns: [4]?*anyopaque = undefined;
    var small_matched: [4]abi_asset_resolver.c.ke_component_id = undefined;
    var count: usize = 0;
    try R.check(e.query_resolve.?(handle.ref, query, &small, small.len, &small_columns[0], &small_matched[0], &count));
    try testing.expectEqual(@as(usize, 16), count);

    var roomy: [32]abi_ecs.c.ke_ecs_segment = undefined;
    var roomy_columns: [32]?*anyopaque = undefined;
    var roomy_matched: [32]abi_asset_resolver.c.ke_component_id = undefined;
    try R.check(e.query_resolve.?(handle.ref, query, &roomy, roomy.len, &roomy_columns[0], &roomy_matched[0], &count));
    try testing.expectEqual(@as(usize, 16), count);
}

test "a query over twelve components resolves with a column for each" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.?.*;

    var cids: [12]abi_asset_resolver.c.ke_component_id = undefined;
    const names = [_][*:0]const u8{ "wide_0", "wide_1", "wide_2", "wide_3", "wide_4", "wide_5", "wide_6", "wide_7", "wide_8", "wide_9", "wide_10", "wide_11" };
    for (&cids, names) |*cid, name| try R.check(e.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = name, .size = 4, .alignment = 4, .fields = null, .field_count = 0 }, cid));

    const entity = try spawn(handle);
    for (cids) |cid| try testing.expect((try attach(handle, entity, cid)) != null);

    const query = (try queryOf(handle, &cids));
    try testing.expect(query != abi_ecs.c.KE_QUERY_INVALID);

    var segs: [4]abi_ecs.c.ke_ecs_segment = undefined;
    var columns: [4 * cids.len]?*anyopaque = undefined;
    var matched: [4 * cids.len]abi_asset_resolver.c.ke_component_id = undefined;
    var count: usize = 0;
    try R.check(e.query_resolve.?(handle.ref, query, &segs, segs.len, &columns[0], &matched[0], &count));

    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqual(@as(u32, 12), segs[0].column_count);
    for (0..12) |t| try testing.expect(segs[0].columns.?[t] != null);
}

test "a query matches only entities having every with component and none of the without components, handing columns of its terms alone" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const pos = try sized(h, "filter_pos");
    const tag = try register(h, &abi_ecs.c.ke_component_params{ .name = "filter_tag", .size = 0, .alignment = 0, .fields = null, .field_count = 0 });
    const hidden = try sized(h, "filter_hidden");
    const plain = try spawn(h);
    _ = try attach(h, plain, pos);
    const tagged = try spawn(h);
    _ = try attach(h, tagged, pos);
    _ = try attach(h, tagged, tag);
    const tagged_hidden = try spawn(h);
    _ = try attach(h, tagged_hidden, pos);
    _ = try attach(h, tagged_hidden, tag);
    _ = try attach(h, tagged_hidden, hidden);

    const terms = [_]abi_ecs.c.ke_ecs_query_term{term(pos, abi_ecs.c.KE_ECS_ACCESS_READ)};
    const query = try registerDesc(h, .{ .terms = &terms, .term_count = 1, .with = @ptrCast(&tag), .with_count = 1, .without = @ptrCast(&hidden), .without_count = 1, .track_changes = false });
    const r = try resolveInto(h, query, 4);
    try testing.expectEqual(1, r.count);
    try testing.expectEqual(1, r.segs[0].count);
    try testing.expectEqual(tagged, r.segs[0].entities.?[0]);
    try testing.expectEqual(1, r.segs[0].column_count);
}

test "a term with no access, or one beyond read and write, is refused" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const pos = try sized(h, "access_pos");
    var query: abi_ecs.c.ke_query_id = 7;
    for ([_]c_uint{ 0, 4 }) |access| {
        const terms = [_]abi_ecs.c.ke_ecs_query_term{term(pos, access)};
        const desc: abi_ecs.c.ke_ecs_query_desc = .{ .terms = &terms, .term_count = 1, .with = null, .with_count = 0, .without = null, .without_count = 0, .track_changes = false };
        try testing.expectEqual(abi_result.c.KE_RESULT_INVALID_ARGUMENT, h.ref.?.query_register.?(h.ref, &desc, &query));
        try testing.expectEqual(abi_ecs.c.KE_QUERY_INVALID, query);
    }
}

test "a description registered twice is shared unless it tracks changes" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const pos = try sized(h, "share_pos");
    const terms = [_]abi_ecs.c.ke_ecs_query_term{term(pos, abi_ecs.c.KE_ECS_ACCESS_READ)};
    try testing.expectEqual(try queryOf(h, &.{pos}), try queryOf(h, &.{pos}));
    try testing.expect(try tracking(h, &terms) != try tracking(h, &terms));
}

test "a tracking query sees a table changed on its first resolve, then only after a written term is resolved or the table gains an entity" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const pos = try sized(h, "change_pos");
    _ = try attach(h, try spawn(h), pos);
    const watch = [_]abi_ecs.c.ke_ecs_query_term{term(pos, abi_ecs.c.KE_ECS_ACCESS_READ)};
    const observer = try tracking(h, &watch);
    const reader = try queryOf(h, &.{pos});
    const writes = [_]abi_ecs.c.ke_ecs_query_term{term(pos, abi_ecs.c.KE_ECS_ACCESS_READ | abi_ecs.c.KE_ECS_ACCESS_WRITE)};
    const writer = try registerDesc(h, .{ .terms = &writes, .term_count = 1, .with = null, .with_count = 0, .without = null, .without_count = 0, .track_changes = false });

    try testing.expectEqual(1, (try resolveInto(h, observer, 4)).changedCount());
    try testing.expectEqual(0, (try resolveInto(h, observer, 4)).changedCount());
    _ = try resolveInto(h, reader, 4);
    try testing.expectEqual(0, (try resolveInto(h, observer, 4)).changedCount());
    _ = try resolveInto(h, writer, 4);
    try testing.expectEqual(1, (try resolveInto(h, observer, 4)).changedCount());
    _ = try attach(h, try spawn(h), pos);
    try testing.expectEqual(1, (try resolveInto(h, observer, 4)).changedCount());
    try testing.expectEqual(0, (try resolveInto(h, observer, 4)).changedCount());
}

test "a segment beyond the resolve's capacity keeps its change for the next resolve" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const pos = try sized(h, "spill_pos");
    const extra = try sized(h, "spill_extra");
    _ = try attach(h, try spawn(h), pos);
    const second = try spawn(h);
    _ = try attach(h, second, pos);
    _ = try attach(h, second, extra);
    const watch = [_]abi_ecs.c.ke_ecs_query_term{term(pos, abi_ecs.c.KE_ECS_ACCESS_READ)};
    const observer = try tracking(h, &watch);
    const first = try resolveInto(h, observer, 1);
    try testing.expectEqual(2, first.count);
    try testing.expectEqual(1, first.changedCount());
    try testing.expectEqual(1, (try resolveInto(h, observer, 4)).changedCount());
}

test "a singleton is seeded once, kept by a second add, matched by no query, and gone after its removal" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const fields = [_]abi_ecs.c.ke_component_field{defaulted("value", abi_ecs_variant.c.KE_VARIANT_INT, 0, 4, intVariant(9))};
    const cid = try register(h, &abi_ecs.c.ke_component_params{ .name = "singleton_value", .size = 4, .alignment = 4, .fields = &fields, .field_count = 1 });
    try testing.expectEqual(null, h.ref.?.singleton_get.?(h.ref, cid));
    var data: ?*anyopaque = null;
    try R.check(h.ref.?.singleton_add.?(h.ref, cid, &data));
    const value: *i32 = @ptrCast(@alignCast(data.?));
    try testing.expectEqual(9, value.*);
    value.* = 4;
    try R.check(h.ref.?.singleton_add.?(h.ref, cid, &data));
    try testing.expectEqual(4, @as(*i32, @ptrCast(@alignCast(h.ref.?.singleton_get.?(h.ref, cid).?))).*);
    try testing.expectEqual(0, (try resolveInto(h, try queryOf(h, &.{cid}), 4)).count);
    try R.check(h.ref.?.singleton_remove.?(h.ref, cid));
    try testing.expectEqual(null, h.ref.?.singleton_get.?(h.ref, cid));
}

test "a singleton of an unregistered component is refused" {
    const h = try made();
    defer h.destroy.?(h.ref);
    var data: ?*anyopaque = null;
    try testing.expectEqual(abi_result.c.KE_RESULT_INVALID_ARGUMENT, h.ref.?.singleton_add.?(h.ref, 0xBEEF, &data));
    try testing.expectEqual(null, data);
}

test "two worlds share no component, entity or query" {
    const a = try made();
    defer a.destroy.?(a.ref);
    const b = try made();
    defer b.destroy.?(b.ref);
    const pos = try sized(a, "world_pos");
    const entity = try spawn(a);
    _ = try attach(a, entity, pos);
    _ = try queryOf(a, &.{pos});
    var meta: abi_ecs.c.ke_component_meta = undefined;
    try testing.expect(!b.ref.?.component_lookup.?(b.ref, "world_pos", &meta));
    try testing.expectEqual(null, b.ref.?.component_get.?(b.ref, entity, pos));
    var r: Resolved = .{};
    try testing.expectEqual(abi_result.c.KE_RESULT_INVALID_ARGUMENT, b.ref.?.query_resolve.?(b.ref, 1, &r.segs, 4, &r.columns[0], &r.matched[0], &r.count));
}

test "a pair is a component of its own, and a wildcard query reports the pair each segment matched" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const likes = try sized(h, "likes");
    const a = try spawn(h);
    const b = try spawn(h);
    const fan = try spawn(h);
    var likes_a: abi_asset_resolver.c.ke_component_id = 0;
    var likes_b: abi_asset_resolver.c.ke_component_id = 0;
    var likes_any: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(h.ref.?.pair.?(h.ref, likes, a, &likes_a));
    try R.check(h.ref.?.pair.?(h.ref, likes, b, &likes_b));
    try R.check(h.ref.?.pair.?(h.ref, likes, abi_ecs.c.KE_ENTITY_WILDCARD, &likes_any));
    try testing.expect(likes_a != likes_b);
    const stored: *i32 = @ptrCast(@alignCast((try attach(h, fan, likes_a)).?));
    stored.* = 7;
    try testing.expectEqual(@as(i32, 7), @as(*i32, @ptrCast(@alignCast(h.ref.?.component_get.?(h.ref, fan, likes_a).?))).*);
    try testing.expect(h.ref.?.component_get.?(h.ref, fan, likes_b) == null);

    var relation: abi_asset_resolver.c.ke_component_id = 0;
    var target: abi_asset_resolver.c.ke_entity = 0;
    try testing.expect(h.ref.?.pair_parts.?(h.ref, likes_a, &relation, &target));
    try testing.expectEqual(likes, relation);
    try testing.expectEqual(a, target);
    try testing.expect(!h.ref.?.pair_parts.?(h.ref, likes, &relation, &target));

    const terms = [_]abi_ecs.c.ke_ecs_query_term{term(likes_any, abi_ecs.c.KE_ECS_ACCESS_READ)};
    const q = try registerDesc(h, .{ .terms = &terms, .term_count = 1, .with = null, .with_count = 0, .without = null, .without_count = 0, .track_changes = false });
    var segs: [4]abi_ecs.c.ke_ecs_segment = undefined;
    var columns: [4]?*anyopaque = undefined;
    var matched: [4]abi_asset_resolver.c.ke_component_id = undefined;
    var count: usize = 0;
    try R.check(h.ref.?.query_resolve.?(h.ref, q, &segs, segs.len, &columns[0], &matched[0], &count));
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqual(likes_a, segs[0].matched.?[0]);
}

test "a removal tracker reports each entity that lost the component once, destroyed ones included" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const pos = try sized(h, "tracked_pos");
    const kept = try spawn(h);
    const stripped = try spawn(h);
    const destroyed = try spawn(h);
    for ([_]abi_asset_resolver.c.ke_entity{ kept, stripped, destroyed }) |e| _ = try attach(h, e, pos);
    var tracker: abi_ecs.c.ke_removal_tracker = 0;
    try R.check(h.ref.?.removal_track.?(h.ref, pos, &tracker));
    try R.check(h.ref.?.component_remove.?(h.ref, stripped, pos));
    try R.check(h.ref.?.entity_destroy.?(h.ref, destroyed));
    var lost: [4]abi_asset_resolver.c.ke_entity = undefined;
    var n: usize = 0;
    try R.check(h.ref.?.removals.?(h.ref, tracker, &lost, lost.len, &n));
    try testing.expectEqual(@as(usize, 2), n);
    try testing.expect(std.mem.indexOfScalar(abi_asset_resolver.c.ke_entity, lost[0..2], stripped) != null);
    try testing.expect(std.mem.indexOfScalar(abi_asset_resolver.c.ke_entity, lost[0..2], destroyed) != null);
    try R.check(h.ref.?.removals.?(h.ref, tracker, &lost, lost.len, &n));
    try testing.expectEqual(@as(usize, 0), n);
}

test "an entity lists its components and the world lists what is registered" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const pos = try sized(h, "listed_pos");
    const vel = try sized(h, "listed_vel");
    const e = try spawn(h);
    _ = try attach(h, e, pos);
    _ = try attach(h, e, vel);
    var cids: [8]abi_asset_resolver.c.ke_component_id = undefined;
    var n: usize = 0;
    try R.check(h.ref.?.entity_components.?(h.ref, e, &cids, cids.len, &n));
    try testing.expectEqual(@as(usize, 2), n);
    try testing.expect(std.mem.indexOfScalar(abi_asset_resolver.c.ke_component_id, cids[0..n], pos) != null);
    try testing.expect(std.mem.indexOfScalar(abi_asset_resolver.c.ke_component_id, cids[0..n], vel) != null);
    try R.check(h.ref.?.components.?(h.ref, &cids, cids.len, &n));
    try testing.expectEqual(@as(usize, 2), n);
}

test "a restore brings back the entities, the listed values and the ids later creations receive" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const pos = try sized(h, "snap_pos");
    const untouched = try sized(h, "snap_free");
    const a = try spawn(h);
    @as(*i32, @ptrCast(@alignCast((try attach(h, a, pos)).?))).* = 1;
    @as(*i32, @ptrCast(@alignCast((try attach(h, a, untouched)).?))).* = 10;
    const listed = [_]abi_asset_resolver.c.ke_component_id{pos};
    var snap: ?*abi_ecs.c.ke_ecs_snapshot = null;
    try R.check(h.ref.?.snapshot.?(h.ref, &listed, listed.len, &snap));
    defer h.ref.?.snapshot_free.?(h.ref, snap);
    const next_then = try spawn(h);

    @as(*i32, @ptrCast(@alignCast(h.ref.?.component_get.?(h.ref, a, pos).?))).* = 2;
    @as(*i32, @ptrCast(@alignCast(h.ref.?.component_get.?(h.ref, a, untouched).?))).* = 20;
    const b = try spawn(h);
    _ = try attach(h, b, pos);
    try R.check(h.ref.?.restore.?(h.ref, snap));

    try testing.expectEqual(@as(i32, 1), @as(*i32, @ptrCast(@alignCast(h.ref.?.component_get.?(h.ref, a, pos).?))).*);
    try testing.expectEqual(@as(i32, 20), @as(*i32, @ptrCast(@alignCast(h.ref.?.component_get.?(h.ref, a, untouched).?))).*);
    try testing.expect(h.ref.?.component_get.?(h.ref, b, pos) == null);
    try testing.expectEqual(next_then, try spawn(h));
}

test "registering a name again with another field table moves every value by field name under the same id" {
    const h = try made();
    defer h.destroy.?(h.ref);
    const V1 = extern struct { hp: i32, speed: f32 };
    const V2 = extern struct { speed: f32, armor: i32, hp: i32 };
    const v1 = [_]abi_ecs.c.ke_component_field{
        .{ .name = "hp", .type = abi_ecs_variant.c.KE_VARIANT_INT, .offset = @offsetOf(V1, "hp"), .size = 4, .default_value = std.mem.zeroes(abi_ecs_variant.c.ke_variant), .enum_names = null, .enum_count = 0 },
        .{ .name = "speed", .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .offset = @offsetOf(V1, "speed"), .size = 4, .default_value = std.mem.zeroes(abi_ecs_variant.c.ke_variant), .enum_names = null, .enum_count = 0 },
    };
    var armor_default = std.mem.zeroes(abi_ecs_variant.c.ke_variant);
    armor_default.type = abi_ecs_variant.c.KE_VARIANT_INT;
    armor_default.unnamed_0.i = 5;
    const v2 = [_]abi_ecs.c.ke_component_field{
        .{ .name = "speed", .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .offset = @offsetOf(V2, "speed"), .size = 4, .default_value = std.mem.zeroes(abi_ecs_variant.c.ke_variant), .enum_names = null, .enum_count = 0 },
        .{ .name = "armor", .type = abi_ecs_variant.c.KE_VARIANT_INT, .offset = @offsetOf(V2, "armor"), .size = 4, .default_value = armor_default, .enum_names = null, .enum_count = 0 },
        .{ .name = "hp", .type = abi_ecs_variant.c.KE_VARIANT_INT, .offset = @offsetOf(V2, "hp"), .size = 4, .default_value = std.mem.zeroes(abi_ecs_variant.c.ke_variant), .enum_names = null, .enum_count = 0 },
    };
    const first = try register(h, &.{ .name = "unit", .size = @sizeOf(V1), .alignment = 4, .fields = &v1, .field_count = v1.len });
    const e = try spawn(h);
    const old: *V1 = @ptrCast(@alignCast((try attach(h, e, first)).?));
    old.* = .{ .hp = 30, .speed = 1.5 };
    const second = try register(h, &.{ .name = "unit", .size = @sizeOf(V2), .alignment = 4, .fields = &v2, .field_count = v2.len });
    try testing.expectEqual(first, second);
    const now: *V2 = @ptrCast(@alignCast(h.ref.?.component_get.?(h.ref, e, second).?));
    try testing.expectEqual(@as(i32, 30), now.hp);
    try testing.expectEqual(@as(f32, 1.5), now.speed);
    try testing.expectEqual(@as(i32, 5), now.armor);
    try testing.expectEqual(@as(usize, @sizeOf(V2)), h.ref.?.component_size.?(h.ref, second));
}

test "a different size with no field table is still refused" {
    const h = try made();
    defer h.destroy.?(h.ref);
    _ = try sized(h, "bare");
    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try testing.expectEqual(abi_result.c.KE_RESULT_INVALID_ARGUMENT, h.ref.?.component_register.?(h.ref, &.{ .name = "bare", .size = 8, .alignment = 4, .fields = null, .field_count = 0 }, &cid));
}

test "creating, filling and destroying an ecs leaves no block allocated" {
    const handle = try made();
    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(handle.ref.?.component_register.?(handle.ref, &abi_ecs.c.ke_component_params{ .name = "leak_probe", .size = 8, .alignment = 4, .fields = null, .field_count = 0 }, &cid));
    const entity = try spawn(handle);
    try testing.expect((try attach(handle, entity, cid)) != null);
    handle.destroy.?(handle.ref);
    try heap.expectNoLeaks();
}

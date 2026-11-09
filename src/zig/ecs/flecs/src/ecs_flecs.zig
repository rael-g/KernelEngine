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

/// A query registered by `queryRegister`. It owns `elem_sizes`, one size per term, and `destroy`
/// frees it.
const RegisteredQuery = struct {
    query: ?*c.ecs_query_t,
    elem_sizes: []usize,
    cids: []abi_asset_resolver.c.ke_component_id,
    term_count: usize,
};

const test_config: abi_ecs_flecs_factory.c.ke_ecs_flecs_config = .{ .world_id_base = 1048576 };

/// The state behind `api.handle`, made by `ke_ecs_flecs_create` and freed by `destroy`. The world
/// has two sources of entity ids that never meet: flecs's own allocator, moved to start at
/// `ke_ecs_flecs_config.world_id_base` and serving `entityCreate`, and the pool of ids from
/// `reserve_low` up to `reserve_end`, below that split, handed out by `entityReserve` with the
/// atomic counter `reserve_next`. A reserved id is only a number until `materializeReserved`
/// makes it alive, once; the `materialized` bitmap, one bit per pool slot, is what keeps a
/// destroyed reserved entity from being revived. `layouts` holds the first field table seen for
/// each component name, which later registrations are compared with and which seeds defaults on
/// attach. `queries` holds one cached query per component and `rqueries` the queries made by
/// `queryRegister`, whose id is the index plus one. `materialized` and the three arrays stay null
/// until something first needs them. Nothing here is locked and no thread is started; only
/// `reserve_next` is touched by several threads.
const State = struct {
    api: abi_ecs.c.ke_ecs,
    world: ?*c.ecs_world_t,

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
};

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
    desc.terms[0].id = @intCast(cid);
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

/// Slot `entity_create`. Ids come from flecs's own allocator, which stays at or above
/// `world_id_base`, so they never coincide with a reserved id.
fn entityCreate(self_in: ?*abi_ecs.c.ke_ecs, out_entity: ?*abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const out = out_entity orelse return R.code(error.InvalidArgument);
    out.* = 0;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    begin();
    const e = c.ecs_new(s.world);
    const rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;
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
        log.warn("every id below world_id_base {d} was reserved", .{s.reserve_end});
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
        const cid: abi_asset_resolver.c.ke_component_id = @truncate(existing);
        const ti = c.ecs_get_type_info(s.world, @intCast(existing));
        const existing_size: usize = if (ti != null) @intCast(ti.*.size) else 0;
        if (existing_size != size) {
            return refuse("component '{s}' already registered as {d} bytes, now {d}", .{ name, existing_size, size });
        }
        const existing_alignment: usize = if (ti != null and size != 0) @intCast(ti.*.alignment) else alignment;
        if (size != 0 and existing_alignment != alignment) {
            return refuse("component '{s}' already registered with alignment {d}, now {d}", .{ name, existing_alignment, alignment });
        }
        if (incoming) |inc| {
            if (layoutOf(s, cid)) |prev| {
                if (firstLayoutDiff(prev, inc)) |i| {
                    return refuse("component '{s}': field {d} differs from the registered layout", .{ name, i });
                }
            } else if (!rememberLayout(s, cid, inc.ptr, field_count)) {
                log.warn("registering component '{s}' failed: out of memory", .{name});
                return R.code(error.OutOfMemory);
            }
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
        _ = findOrCreateQuery(s, @truncate(e));
        out.* = @truncate(e);
        return R.ok;
    }

    var cdesc: c.ecs_component_desc_t = std.mem.zeroes(c.ecs_component_desc_t);
    cdesc.entity = e;
    cdesc.type.size = @intCast(size);
    cdesc.type.alignment = @intCast(alignment);
    const cid: abi_asset_resolver.c.ke_component_id = @truncate(c.ecs_component_init(s.world, &cdesc));
    rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;

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

    const cid: abi_asset_resolver.c.ke_component_id = @truncate(e);
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

    const already_had = c.ecs_has_id(s.world, @intCast(entity), @intCast(component));
    c.ecs_add_id(s.world, @intCast(entity), @intCast(component));
    var rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;
    const ti = c.ecs_get_type_info(s.world, @intCast(component));
    if (ti == null or ti.*.size <= 0) return R.ok;

    const slot = c.ecs_get_mut_id(s.world, @intCast(entity), @intCast(component));
    rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;
    if (!already_had) {
        const bytes: [*]u8 = @ptrCast(slot);
        @memset(bytes[0..@intCast(ti.*.size)], 0);
        if (layoutOf(s, component)) |fields| {
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
    if (c.ecs_is_alive(s.world, @intCast(entity))) c.ecs_remove_id(s.world, @intCast(entity), @intCast(component));
    return outcome();
}

/// Slot `component_get`. The bytes of a component for a living entity that holds it, otherwise
/// null.
fn componentGet(self_in: ?*abi_ecs.c.ke_ecs, entity: abi_asset_resolver.c.ke_entity, component: abi_asset_resolver.c.ke_component_id) callconv(.c) ?*anyopaque {
    const self = self_in orelse return null;
    if (self.handle == null or entity == 0 or component == 0) return null;
    const s = stateOf(self);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return null;
    if (!c.ecs_has_id(s.world, @intCast(entity), @intCast(component))) return null;
    return @constCast(c.ecs_get_id(s.world, @intCast(entity), @intCast(component)));
}

/// Slot `component_size`. The byte size flecs holds for a component id, zero for an unknown id or
/// a tag.
fn componentSize(self_in: ?*abi_ecs.c.ke_ecs, cid: abi_asset_resolver.c.ke_component_id) callconv(.c) usize {
    const self = self_in orelse return 0;
    if (self.handle == null or cid == 0) return 0;
    const s = stateOf(self);
    const ti = c.ecs_get_type_info(s.world, @intCast(cid));
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

/// Slot `query_register`. Builds a flecs query with one term per component id and records the byte
/// size of each term for `queryResolve`; a tuple registered before, in the same order, answers the
/// id it got then and builds nothing. The id counts from one, so it is never the invalid id. A null
/// argument, a zero count, more ids than a flecs query has terms and a query flecs refuses are
/// invalid arguments; a flecs query created before a later step fails is finalized first.
fn queryRegister(
    self_in: ?*abi_ecs.c.ke_ecs,
    cids: [*c]const abi_asset_resolver.c.ke_component_id,
    cid_count: usize,
    out_query: ?*abi_ecs.c.ke_query_id,
) callconv(.c) abi_result.c.ke_result {
    const out = out_query orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_QUERY_INVALID;
    const self = self_in orelse return R.code(error.InvalidArgument);
    var desc: c.ecs_query_desc_t = std.mem.zeroes(c.ecs_query_desc_t);
    if (self.handle == null or cids == null or cid_count == 0) return R.code(error.InvalidArgument);
    if (cid_count > desc.terms.len) {
        log.warn("a query of {d} terms is more than the {d} a flecs query holds", .{ cid_count, desc.terms.len });
        return R.code(error.InvalidArgument);
    }
    const s = stateOf(self);

    if (s.rqueries) |existing| {
        for (existing[0..s.rquery_count], 1..) |*rq, id| {
            if (std.mem.eql(abi_asset_resolver.c.ke_component_id, rq.cids, cids[0..cid_count])) {
                out.* = @intCast(id);
                return R.ok;
            }
        }
    }

    for (0..cid_count) |i| desc.terms[i].id = @intCast(cids[i]);
    begin();
    const query = c.ecs_query_init(s.world, &desc);
    const rc = outcome();
    const q = query orelse {
        if (rc == abi_result.c.KE_OK) log.warn("flecs refused the query", .{});
        return R.code(error.InvalidArgument);
    };
    if (rc != abi_result.c.KE_OK) {
        c.ecs_query_fini(q);
        return rc;
    }
    const elem_sizes = heap.gpa.alloc(usize, cid_count) catch {
        c.ecs_query_fini(q);
        return R.code(error.OutOfMemory);
    };
    const owned_cids = heap.gpa.dupe(abi_asset_resolver.c.ke_component_id, cids[0..cid_count]) catch {
        heap.gpa.free(elem_sizes);
        c.ecs_query_fini(q);
        return R.code(error.OutOfMemory);
    };

    if (s.rquery_count == s.rquery_capacity) {
        const new_cap: usize = if (s.rquery_capacity != 0) s.rquery_capacity * 2 else 8;
        const new_buf = heap.gpa.alloc(RegisteredQuery, new_cap) catch {
            heap.gpa.free(owned_cids);
            heap.gpa.free(elem_sizes);
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

    const rq = &s.rqueries.?[s.rquery_count];
    rq.query = q;
    rq.term_count = cid_count;
    rq.elem_sizes = elem_sizes;
    rq.cids = owned_cids;
    for (0..cid_count) |i| {
        const ti = c.ecs_get_type_info(s.world, @intCast(cids[i]));
        rq.elem_sizes[i] = if (ti != null) @intCast(ti.*.size) else 0;
    }
    s.rquery_count += 1;
    out.* = @intCast(s.rquery_count);
    return R.ok;
}

/// Slot `query_resolve`. Runs the query from its start and writes one segment per matching table:
/// its entities, its count and one column per term, with the columns of segment n starting at n
/// times the term count in the caller's array. Column pointers refer into the world's storage and
/// stay valid until the next structural change, and a zero-size term's column is null. Segments
/// beyond the caller's capacity are counted but not written, so the count written to out_count is
/// the total. Any invalid argument or unknown query leaves that count at zero.
fn queryResolve(
    self_in: ?*abi_ecs.c.ke_ecs,
    query: abi_ecs.c.ke_query_id,
    out_segments: [*c]abi_ecs.c.ke_ecs_segment,
    max_segments: usize,
    out_columns: [*c]?*anyopaque,
    out_count: [*c]usize,
) callconv(.c) abi_result.c.ke_result {
    if (out_count == null) return R.code(error.InvalidArgument);
    out_count.* = 0;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or query == abi_ecs.c.KE_QUERY_INVALID or out_segments == null or out_columns == null or max_segments == 0)
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
        seg += 1;
    }
    const rc = outcome();
    if (rc != abi_result.c.KE_OK) return rc;
    out_count.* = seg;
    return R.ok;
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
            heap.gpa.free(rqs[i].elem_sizes);
            heap.gpa.free(rqs[i].cids);
        }
        heap.gpa.free(rqs[0..s.rquery_capacity]);
    }
    if (s.layouts) |ls| {
        for (ls[0..s.layout_count]) |l| freeFields(@constCast(l.fields[0..l.field_count]));
        heap.gpa.free(ls[0..s.layout_capacity]);
    }
    if (s.materialized) |m| heap.gpa.free(m);
    if (s.world) |w| _ = c.ecs_fini(w);

    heap.gpa.destroy(s);
}

/// The factory the plugin exports. A null config takes the header's defaults. A failure after the world exists finalizes it and frees the state,
/// leaving the handle zeroed.
export fn ke_ecs_flecs_create(
    config: ?*const abi_ecs_flecs_factory.c.ke_ecs_flecs_config,
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

fn create(config: ?*const abi_ecs_flecs_factory.c.ke_ecs_flecs_config) R.Error!abi_ecs.c.ke_ecs_handle {
    const world_id_base = (config orelse {
        log.warn("creating the ECS needs its config", .{});
        return error.InvalidArgument;
    }).*.world_id_base;
    if (world_id_base == 0) {
        log.warn("creating the ECS needs a world id base above 0, the capacity of entity_reserve", .{});
        return error.InvalidArgument;
    }

    installFlecsOsApi();

    const s = heap.gpa.create(State) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(s);
    s.* = .{
        .api = std.mem.zeroes(abi_ecs.c.ke_ecs),
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
        .layouts = null,
        .layout_count = 0,
        .layout_capacity = 0,
    };

    s.world = c.ecs_init();
    if (s.world == null) return error.NotInitialized;
    errdefer _ = c.ecs_fini(s.world);

    s.reserve_low = @intCast(c.ecs_get_max_id(s.world) + 1);
    if (world_id_base <= s.reserve_low) {
        log.warn("world_id_base {d} leaves no room below it for the reserve pool", .{world_id_base});
        return error.InvalidArgument;
    }
    if (c.ecs_entity_range_new(s.world, world_id_base, 0)) |range| {
        c.ecs_entity_range_set(s.world, range);
    } else {
        log.warn("flecs would not keep its ids clear of the reserve pool", .{});
        return error.NotInitialized;
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
    s.api.component_field_write = componentFieldWrite;
    s.api.query_register = queryRegister;
    s.api.query_resolve = queryResolve;

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
    var query: abi_ecs.c.ke_query_id = abi_ecs.c.KE_QUERY_INVALID;
    try R.check(h.ref.?.query_register.?(h.ref, cids.ptr, cids.len, &query));
    return query;
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

test "componentRegister rejects a second layout the size check cannot tell apart" {
    const handle = try made();
    defer handle.destroy.?(handle.ref);

    const first = try register(handle, &abi_ecs.c.ke_component_params{ .name = "swapped", .size = 8, .alignment = 4, .fields = &swapped_a, .field_count = swapped_a.len });
    try testing.expect(first != 0);

    try testing.expectError(error.InvalidArgument, register(handle, &abi_ecs.c.ke_component_params{ .name = "swapped", .size = 8, .alignment = 4, .fields = &swapped_b, .field_count = swapped_b.len }));
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
    _ = c.ecs_get_mut_id(stateOf(handle.ref.?).world, @intCast(entity), @intCast(tag));
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
    try testing.expect(reserved < test_config.world_id_base);

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const created = try spawn(handle);
        try testing.expect(created >= test_config.world_id_base);
    }
}

test "reserving past the pool's capacity reports exhaustion instead of colliding" {
    var config = test_config;
    var probe: abi_ecs.c.ke_ecs_handle = undefined;
    try R.check(ke_ecs_flecs_create(&config, &probe));
    const low = stateOf(probe.ref.?).reserve_low;
    probe.destroy.?(probe.ref);

    config.world_id_base = low + 4;
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
    var config = abi_ecs_flecs_factory.c.ke_ecs_flecs_config{ .world_id_base = 1 };
    var handle: abi_ecs.c.ke_ecs_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_ecs_flecs_create(&config, &handle)));
    try testing.expect(handle.ref == null);
}

test "a caller may move the split between the two id allocators" {
    var config = abi_ecs_flecs_factory.c.ke_ecs_flecs_config{ .world_id_base = 1_000_000 };
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
    var count: usize = 0;
    try R.check(e.query_resolve.?(handle.ref, query, &small, small.len, &small_columns[0], &count));
    try testing.expectEqual(@as(usize, 16), count);

    var roomy: [32]abi_ecs.c.ke_ecs_segment = undefined;
    var roomy_columns: [32]?*anyopaque = undefined;
    try R.check(e.query_resolve.?(handle.ref, query, &roomy, roomy.len, &roomy_columns[0], &count));
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
    var count: usize = 0;
    try R.check(e.query_resolve.?(handle.ref, query, &segs, segs.len, &columns[0], &count));

    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqual(@as(u32, 12), segs[0].column_count);
    for (0..12) |t| try testing.expect(segs[0].columns.?[t] != null);
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

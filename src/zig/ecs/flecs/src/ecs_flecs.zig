
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const c = @import("c.zig").c;
const component_fields = @import("component_fields").Fields(c);
const heap = @import("heap");

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

const LayoutEntry = struct {
    cid: c.ke_component_id,
    fields: [*]const c.ke_component_field,
    field_count: u32,
};

const RegisteredQuery = struct {
    query: ?*c.ecs_query_t,
    elem_sizes: [c.KE_QUERY_MAX_TERMS]usize,
    term_count: usize,
};

const default_world_id_base: u32 = 1 << 20;

const State = struct {
    api: c.ke_ecs,
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

fn nameEquals(a: [*c]const u8, b: [*c]const u8) bool {
    if (a == null or b == null) return a == b;
    return std.mem.orderZ(u8, @ptrCast(a), @ptrCast(b)) == .eq;
}

fn firstLayoutDiff(a: []const c.ke_component_field, b: []const c.ke_component_field) ?usize {
    const common = @min(a.len, b.len);
    for (0..common) |i| {
        if (a[i].type != b[i].type or a[i].offset != b[i].offset or a[i].size != b[i].size) return i;
        if (!nameEquals(a[i].name, b[i].name)) return i;
    }
    return if (a.len != b.len) common else null;
}

fn layoutFitsSize(fields: []const c.ke_component_field, element_size: usize) bool {
    for (fields) |f| {
        if (@as(usize, f.offset) + @as(usize, f.size) > element_size) return false;
    }
    return true;
}

fn layoutOf(s: *State, cid: c.ke_component_id) ?[]const c.ke_component_field {
    const ls = s.layouts orelse return null;
    for (0..s.layout_count) |i| {
        if (ls[i].cid == cid) return ls[i].fields[0..ls[i].field_count];
    }
    return null;
}

fn rememberLayout(
    s: *State,
    cid: c.ke_component_id,
    fields: [*]const c.ke_component_field,
    field_count: u32,
) bool {
    if (s.layout_count == s.layout_capacity) {
        const new_cap: usize = if (s.layout_capacity != 0) s.layout_capacity * 2 else 8;
        const new_buf = heap.gpa.alloc(LayoutEntry, new_cap) catch return false;
        if (s.layouts) |old| {
            @memcpy(new_buf[0..s.layout_count], old[0..s.layout_count]);
            heap.gpa.free(old[0..s.layout_capacity]);
        }
        s.layouts = new_buf.ptr;
        s.layout_capacity = new_cap;
    }
    s.layouts.?[s.layout_count] = .{ .cid = cid, .fields = fields, .field_count = field_count };
    s.layout_count += 1;
    return true;
}

threadlocal var layout_msg_buf: [256]u8 = undefined;

fn layoutMessage(comptime fmt: []const u8, args: anytype) [*c]const u8 {
    const dst = layout_msg_buf[0 .. layout_msg_buf.len - 1];
    const written = std.fmt.bufPrint(dst, fmt, args) catch dst;
    layout_msg_buf[written.len] = 0;
    return @ptrCast(&layout_msg_buf);
}

fn entityCreate(self_in: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    const s = stateOf(self);
    return @intCast(c.ecs_new(s.world));
}

fn entityReserve(self_in: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    const s = stateOf(self);
    const offset = s.reserve_next.fetchAdd(1, .monotonic);
    if (offset >= s.reserve_end - s.reserve_low) return 0;
    return @as(c.ke_entity, s.reserve_low) + offset;
}

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
    fields: [*c]const c.ke_component_field,
    field_count: u32,
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

    const incoming: ?[]const c.ke_component_field =
        if (fields != null and field_count > 0) fields[0..field_count] else null;

    if (incoming) |inc| {
        if (!layoutFitsSize(inc, size)) {
            E.fail(out_error, .invalid_argument, layoutMessage(
                "component '{s}': field table describes bytes past its {d}-byte size",
                .{ name, size },
            ), @src());
            return 0;
        }
    }

    const existing = c.ecs_lookup(s.world, name);
    if (existing != 0) {
        const cid: c.ke_component_id = @truncate(existing);
        const ti = c.ecs_get_type_info(s.world, @intCast(existing));
        const existing_size: usize = if (ti != null) @intCast(ti.*.size) else 0;
        if (existing_size != size) {
            E.fail(out_error, .invalid_argument, layoutMessage(
                "component '{s}' already registered as {d} bytes, now {d}",
                .{ name, existing_size, size },
            ), @src());
            return 0;
        }
        if (incoming) |inc| {
            if (layoutOf(s, cid)) |prev| {
                if (firstLayoutDiff(prev, inc)) |i| {
                    E.fail(out_error, .invalid_argument, layoutMessage(
                        "component '{s}': field {d} differs from the registered layout",
                        .{ name, i },
                    ), @src());
                    return 0;
                }
            } else if (!rememberLayout(s, cid, inc.ptr, field_count)) {
                E.fail(out_error, .out_of_memory, "component layout registry allocation failed", @src());
                return 0;
            }
        }
        _ = findOrCreateQuery(s, cid);
        return cid;
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

    if (incoming) |inc| {
        if (!rememberLayout(s, cid, inc.ptr, field_count)) {
            E.fail(out_error, .out_of_memory, "component layout registry allocation failed", @src());
            return 0;
        }
    }

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
        const cid: c.ke_component_id = @truncate(e);
        out_meta.*.cid = cid;
        out_meta.*.size = @intCast(ti.*.size);
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

fn componentAdd(self_in: ?*c.ke_ecs, entity: c.ke_entity, component: c.ke_component_id) callconv(.c) ?*anyopaque {
    const self = self_in orelse return null;
    if (self.handle == null or entity == 0 or component == 0) return null;
    const s = stateOf(self);
    materializeReserved(s, entity);
    if (!c.ecs_is_alive(s.world, @intCast(entity))) return null;

    const already_had = c.ecs_has_id(s.world, @intCast(entity), @intCast(component));
    c.ecs_add_id(s.world, @intCast(entity), @intCast(component));
    const ti = c.ecs_get_type_info(s.world, @intCast(component));
    if (ti == null or ti.*.size <= 0) return null;

    const slot = c.ecs_get_mut_id(s.world, @intCast(entity), @intCast(component));
    if (!already_had) {
        if (layoutOf(s, component)) |fields| {
            component_fields.seedDefaults(slot, fields.ptr, @intCast(fields.len));
        }
    }
    return slot;
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
    if (s.layouts) |ls| heap.gpa.free(ls[0..s.layout_capacity]);
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
        .layouts = null,
        .layout_count = 0,
        .layout_capacity = 0,
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
    const first = handle.ref.*.component_register.?(handle.ref, "dup_name", 8, null, 0, &out_error);
    try testing.expect(first != 0);
    try testing.expect(out_error == null);

    const second = handle.ref.*.component_register.?(handle.ref, "dup_name", 16, null, 0, &out_error);
    try testing.expectEqual(@as(c.ke_component_id, 0), second);
    try testing.expect(out_error != null);
}

fn field(name: [*c]const u8, t: c.ke_variant_type, offset: u32, size: u32) c.ke_component_field {
    return .{
        .name = name,
        .type = t,
        .offset = offset,
        .size = size,
        .default_value = std.mem.zeroes(c.ke_variant),
    };
}

const swapped_a = [_]c.ke_component_field{
    field("layers", c.KE_VARIANT_INT, 0, 4),
    field("ior", c.KE_VARIANT_FLOAT, 4, 4),
};
const swapped_b = [_]c.ke_component_field{
    field("ior", c.KE_VARIANT_FLOAT, 0, 4),
    field("layers", c.KE_VARIANT_INT, 4, 4),
};

test "two layouts of the same size disagree at the first field that moved" {
    try testing.expectEqual(@as(?usize, 0), firstLayoutDiff(&swapped_a, &swapped_b));
    try testing.expectEqual(@as(?usize, null), firstLayoutDiff(&swapped_a, &swapped_a));
}

test "a field that kept its place but changed meaning still counts as a difference" {
    const as_float = [_]c.ke_component_field{field("value", c.KE_VARIANT_FLOAT, 0, 4)};
    const as_int = [_]c.ke_component_field{field("value", c.KE_VARIANT_INT, 0, 4)};
    try testing.expectEqual(@as(?usize, 0), firstLayoutDiff(&as_float, &as_int));
}

test "a layout that ran out of fields disagrees at the first one the other still has" {
    const shorter = [_]c.ke_component_field{field("ior", c.KE_VARIANT_FLOAT, 0, 4)};
    try testing.expectEqual(@as(?usize, 1), firstLayoutDiff(&shorter, &swapped_b));
    try testing.expectEqual(@as(?usize, 1), firstLayoutDiff(&swapped_b, &shorter));
}

test "a table reaching past the component's size belongs to another type" {
    try testing.expect(layoutFitsSize(&swapped_a, 8));
    try testing.expect(!layoutFitsSize(&swapped_a, 7));
    try testing.expect(layoutFitsSize(&swapped_a, 16));
}

test "componentRegister rejects a second layout the size check cannot tell apart" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);

    var out_error: ?*c.ke_error = null;
    const first = handle.ref.*.component_register.?(handle.ref, "swapped", 8, &swapped_a, swapped_a.len, &out_error);
    try testing.expect(first != 0);
    try testing.expect(out_error == null);

    const second = handle.ref.*.component_register.?(handle.ref, "swapped", 8, &swapped_b, swapped_b.len, &out_error);
    try testing.expectEqual(@as(c.ke_component_id, 0), second);
    try testing.expect(out_error != null);
}

test "componentRegister accepts a second registration describing the same layout" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);

    var out_error: ?*c.ke_error = null;
    const first = handle.ref.*.component_register.?(handle.ref, "agreed", 8, &swapped_a, swapped_a.len, &out_error);
    const second = handle.ref.*.component_register.?(handle.ref, "agreed", 8, &swapped_a, swapped_a.len, &out_error);
    try testing.expectEqual(first, second);
    try testing.expect(out_error == null);
}

test "a registrant with no table still joins one that has one, on size alone" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);

    var out_error: ?*c.ke_error = null;
    const described = handle.ref.*.component_register.?(handle.ref, "partial", 8, &swapped_a, swapped_a.len, &out_error);
    const tableless = handle.ref.*.component_register.?(handle.ref, "partial", 8, null, 0, &out_error);
    try testing.expectEqual(described, tableless);
    try testing.expect(out_error == null);
}

test "the table of the first registrant to carry one describes the component afterwards" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);

    const tableless = handle.ref.*.component_register.?(handle.ref, "late_table", 8, null, 0, null);
    _ = handle.ref.*.component_register.?(handle.ref, "late_table", 8, &swapped_a, swapped_a.len, null);

    var meta: c.ke_component_meta = undefined;
    try testing.expect(handle.ref.*.component_lookup.?(handle.ref, "late_table", &meta, null));
    try testing.expectEqual(tableless, meta.cid);
    try testing.expectEqual(@as(u32, swapped_a.len), meta.field_count);
    try testing.expect(meta.fields != null);
}

test "componentRegister refuses a table describing bytes the component does not have" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);

    var out_error: ?*c.ke_error = null;
    const cid = handle.ref.*.component_register.?(handle.ref, "too_small", 4, &swapped_a, swapped_a.len, &out_error);
    try testing.expectEqual(@as(c.ke_component_id, 0), cid);
    try testing.expect(out_error != null);
}

test "componentRegister is idempotent for a repeated identical size" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);

    var out_error: ?*c.ke_error = null;
    const first = handle.ref.*.component_register.?(handle.ref, "same_name", 12, null, 0, &out_error);
    const second = handle.ref.*.component_register.?(handle.ref, "same_name", 12, null, 0, &out_error);
    try testing.expectEqual(first, second);
    try testing.expect(out_error == null);
}

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

    const cid = e.component_register.?(handle.ref, "reserve_probe", 4, null, 0, null);
    const reserved = e.entity_reserve.?(handle.ref);
    try testing.expect(e.component_get.?(handle.ref, reserved, cid) == null);

    e.entity_materialize.?(handle.ref, reserved);
    try testing.expect(e.component_add.?(handle.ref, reserved, cid) != null);
}

test "attaching to a reserved id materializes it without a separate call" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const cid = e.component_register.?(handle.ref, "attach_probe", 4, null, 0, null);
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

    const cid = e.component_register.?(handle.ref, "twice_probe", 4, null, 0, null);
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

    const cid = e.component_register.?(handle.ref, "owned_probe", 4, null, 0, null);
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

    const cid = e.component_register.?(handle.ref, "revive_probe", 4, null, 0, null);
    const reserved = e.entity_reserve.?(handle.ref);
    try testing.expect(e.component_add.?(handle.ref, reserved, cid) != null);

    e.entity_destroy.?(handle.ref, reserved);
    try testing.expect(e.component_add.?(handle.ref, reserved, cid) == null);
    try testing.expect(e.component_get.?(handle.ref, reserved, cid) == null);
}

const Layered = extern struct {
    layers: u32,
    ior: f32,
};

fn defaulted(name: [*c]const u8, t: c.ke_variant_type, offset: u32, size: u32, v: c.ke_variant) c.ke_component_field {
    return .{ .name = name, .type = t, .offset = offset, .size = size, .default_value = v };
}

fn intVariant(i: i64) c.ke_variant {
    var v = std.mem.zeroes(c.ke_variant);
    v.type = c.KE_VARIANT_INT;
    v.unnamed_0.i = i;
    return v;
}

fn floatVariant(f: f64) c.ke_variant {
    var v = std.mem.zeroes(c.ke_variant);
    v.type = c.KE_VARIANT_FLOAT;
    v.unnamed_0.f = f;
    return v;
}

const layered_fields = [_]c.ke_component_field{
    defaulted("layers", c.KE_VARIANT_INT, 0, 4, intVariant(1)),
    defaulted("ior", c.KE_VARIANT_FLOAT, 4, 4, floatVariant(1.5)),
};

test "attaching a component seeds the defaults its field table declares" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const cid = e.component_register.?(handle.ref, "layered", @sizeOf(Layered), &layered_fields, layered_fields.len, null);
    try testing.expect(cid != 0);

    const entity = e.entity_create.?(handle.ref);
    const slot = e.component_add.?(handle.ref, entity, cid) orelse return error.MissingComponent;
    const v: *const Layered = @ptrCast(@alignCast(slot));

    try testing.expectEqual(@as(u32, 1), v.layers);
    try testing.expectEqual(@as(f32, 1.5), v.ior);
}

test "attaching a component that is already there keeps the value it holds" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const cid = e.component_register.?(handle.ref, "layered_twice", @sizeOf(Layered), &layered_fields, layered_fields.len, null);
    const entity = e.entity_create.?(handle.ref);

    const first: *Layered = @ptrCast(@alignCast(e.component_add.?(handle.ref, entity, cid).?));
    first.layers = 0b1010;

    const second: *const Layered = @ptrCast(@alignCast(e.component_add.?(handle.ref, entity, cid).?));
    try testing.expectEqual(@as(u32, 0b1010), second.layers);
}

test "a component registered without a field table still attaches zeroed" {
    const handle = ke_ecs_flecs_create(null, null);
    defer handle.destroy.?(handle.ref);
    const e = handle.ref.*;

    const cid = e.component_register.?(handle.ref, "untabled", @sizeOf(Layered), null, 0, null);
    const entity = e.entity_create.?(handle.ref);
    const v: *const Layered = @ptrCast(@alignCast(e.component_add.?(handle.ref, entity, cid).?));

    try testing.expectEqual(@as(u32, 0), v.layers);
}

test "creating, filling and destroying an ecs leaves no block allocated" {
    const handle = ke_ecs_flecs_create(null, null);
    const cid = handle.ref.*.component_register.?(handle.ref, "leak_probe", 8, null, 0, null);
    const e = handle.ref.*.entity_create.?(handle.ref);
    try testing.expect(handle.ref.*.component_add.?(handle.ref, e, cid) != null);
    handle.destroy.?(handle.ref);
    try heap.expectNoLeaks();
}

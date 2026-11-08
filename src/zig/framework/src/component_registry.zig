//! The component registry: how a scene fills each component, and the short names a scene may
//! write for one.

const abi_framework = @import("abi_framework");
const abi_spatial_contract = @import("abi_spatial_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_scene_loader = @import("abi_scene_loader");
const abi_component_registry = @import("abi_component_registry");
const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");
const abi_spatial = @import("abi_spatial");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.framework);


const apply_initial_capacity: u32 = 16;

/// One entry per component id. The apply half (`fn_ptr`, `ctx`) and the fields half (`fields`,
/// `field_count`) are written by separate registration slots, so either half may stay unset.
const ApplyEntry = struct {
    cid: abi_asset_resolver.c.ke_component_id,
    fn_ptr: abi_component_registry.c.ke_component_apply_fn,
    ctx: ?*anyopaque,
    fields: ?[*]const abi_ecs.c.ke_component_field,
    field_count: u32,
};

/// One short name a scene may write for a component, and the full name it stands for. Both are
/// copies the registry owns.
const Alias = struct {
    alias: [:0]u8,
    name: [:0]u8,
};

/// The state behind one registry, embedding its vtable as `api`, whose handle points back at it.
/// The ecs is borrowed and never freed. `apply_registry` stays null until the first registration,
/// and `apply_capacity` is the length of the buffer it points to, which is what `destroy` frees.
const State = struct {
    api: abi_component_registry.c.ke_component_registry,
    ecs: *abi_ecs.c.ke_ecs,

    apply_registry: ?[*]ApplyEntry = null,
    apply_count: u32 = 0,
    apply_capacity: u32 = 0,

    aliases: std.ArrayList(Alias) = .empty,
};

fn stateOf(self: *abi_component_registry.c.ke_component_registry) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// Returns the entry for the given component id, appending an empty one when there is none. Both
/// registration slots go through it. Appending can replace the whole buffer, so an entry pointer
/// kept across a later call is not valid after that call. On an allocation failure the registry
/// is unchanged.
fn entryFor(s: *State, cid: abi_asset_resolver.c.ke_component_id) error{OutOfMemory}!*ApplyEntry {
    if (s.apply_registry) |reg| {
        for (reg[0..s.apply_count]) |*entry| {
            if (entry.cid == cid) return entry;
        }
    }

    if (s.apply_count == s.apply_capacity) {
        const cap = if (s.apply_capacity != 0) s.apply_capacity * 2 else apply_initial_capacity;
        const new_buf = try heap.gpa.alloc(ApplyEntry, cap);
        if (s.apply_registry) |old| {
            @memcpy(new_buf[0..s.apply_count], old[0..s.apply_count]);
            heap.gpa.free(old[0..s.apply_capacity]);
        }
        s.apply_registry = new_buf.ptr;
        s.apply_capacity = cap;
    }

    const entry = &s.apply_registry.?[s.apply_count];
    entry.* = .{ .cid = cid, .fn_ptr = null, .ctx = null, .fields = null, .field_count = 0 };
    s.apply_count += 1;
    return entry;
}

/// Slot `register_component_apply`. Sets the callback and context of a component id, leaving its
/// field table alone, and replaces a callback registered before. Fails as an invalid argument for
/// a null registry or callback, and as out of memory when the registry cannot grow.
fn registerComponentApply(
    self_in: ?*abi_component_registry.c.ke_component_registry,
    cid: abi_asset_resolver.c.ke_component_id,
    apply_fn: abi_component_registry.c.ke_component_apply_fn,
    ctx: ?*anyopaque,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or apply_fn == null) return R.code(error.InvalidArgument);
    const entry = entryFor(stateOf(self), cid) catch |err| return R.code(err);
    entry.fn_ptr = apply_fn;
    entry.ctx = ctx;
    return R.ok;
}

/// Slot `register_component_fields`. Sets the field table of a component id, leaving its callback
/// alone; the table is borrowed, not copied. Fails as an invalid argument for a null registry or
/// table or a zero count, and as out of memory when the registry cannot grow.
fn registerComponentFields(
    self_in: ?*abi_component_registry.c.ke_component_registry,
    cid: abi_asset_resolver.c.ke_component_id,
    fields: [*c]const abi_ecs.c.ke_component_field,
    field_count: u32,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or fields == null or field_count == 0) return R.code(error.InvalidArgument);
    const entry = entryFor(stateOf(self), cid) catch |err| return R.code(err);
    entry.fields = fields;
    entry.field_count = field_count;
    return R.ok;
}

/// Slot `get_component_fields`. Returns the table registered for the id and writes its length to
/// `out_count` when that is non-null. An id whose entry has no fields returns null, not
/// an empty table.
fn getComponentFields(
    self_in: ?*abi_component_registry.c.ke_component_registry,
    cid: abi_asset_resolver.c.ke_component_id,
    out_count: [*c]u32,
) callconv(.c) [*c]const abi_ecs.c.ke_component_field {
    const self = self_in orelse return null;
    if (self.handle == null) return null;
    const s = stateOf(self);
    const reg = s.apply_registry orelse return null;
    for (reg[0..s.apply_count]) |entry| {
        if (entry.cid != cid) continue;
        const f = entry.fields orelse return null;
        if (out_count != null) out_count.* = entry.field_count;
        return f;
    }
    return null;
}

/// Slot `get_component_apply`. Returns the callback registered for the id and writes its context.
/// The context is written whenever the id has an entry, so a null callback can still come back
/// together with a context.
fn getComponentApply(
    self_in: ?*abi_component_registry.c.ke_component_registry,
    cid: abi_asset_resolver.c.ke_component_id,
    out_ctx: [*c]?*anyopaque,
) callconv(.c) abi_component_registry.c.ke_component_apply_fn {
    const self = self_in orelse return null;
    if (self.handle == null) return null;
    const s = stateOf(self);
    const reg = s.apply_registry orelse return null;
    for (reg[0..s.apply_count]) |entry| {
        if (entry.cid != cid) continue;
        if (out_ctx != null) out_ctx.* = entry.ctx;
        return entry.fn_ptr;
    }
    return null;
}

/// Slot `register_component_alias`. Records the pair unless it is already recorded; two pairs
/// with one alias are kept both, which is what makes the alias ambiguous. Fails as an invalid
/// argument for a null registry, alias or name, and as out of memory when a copy cannot be made.
fn registerComponentAlias(
    self_in: ?*abi_component_registry.c.ke_component_registry,
    alias: [*c]const u8,
    name: [*c]const u8,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or alias == null or name == null) return R.code(error.InvalidArgument);
    return R.of(registerAlias(stateOf(self), std.mem.span(alias), std.mem.span(name)));
}

fn registerAlias(s: *State, alias: []const u8, name: []const u8) error{OutOfMemory}!void {
    for (s.aliases.items) |a| {
        if (std.mem.eql(u8, a.alias, alias) and std.mem.eql(u8, a.name, name)) return;
    }
    const alias_copy = try heap.gpa.dupeZ(u8, alias);
    errdefer heap.gpa.free(alias_copy);
    const name_copy = try heap.gpa.dupeZ(u8, name);
    errdefer heap.gpa.free(name_copy);
    try s.aliases.append(heap.gpa, .{ .alias = alias_copy, .name = name_copy });
}

/// Slot `resolve_component`. A name the ecs knows wins when no alias shares it; an alias with a
/// single full name, and no component registered under the alias itself, resolves to that name.
/// A name nothing answers to fails as not found and an ambiguous one as an invalid argument, each
/// logging the name and, when ambiguous, its candidates.
fn resolveComponent(
    self_in: ?*abi_component_registry.c.ke_component_registry,
    name: [*c]const u8,
    out_meta: [*c]abi_ecs.c.ke_component_meta,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or name == null or out_meta == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const e = s.ecs;
    const name_s = std.mem.span(name);

    var target: ?[:0]const u8 = null;
    var candidates: u32 = 0;
    var buf: [256]u8 = undefined;
    var list = std.Io.Writer.fixed(&buf);
    for (s.aliases.items) |a| {
        if (!std.mem.eql(u8, a.alias, name_s)) continue;
        candidates += 1;
        target = a.name;
        list.print("{s}'{s}'", .{ if (candidates > 1) " and " else "", a.name }) catch {};
    }

    const direct = e.component_lookup.?(e, name, out_meta);
    if (candidates == 0) {
        if (direct) return R.ok;
        log.warn("no component is registered as '{s}'", .{name_s});
        return R.code(error.NotFound);
    }
    if (candidates == 1 and !direct) {
        if (e.component_lookup.?(e, target.?.ptr, out_meta)) return R.ok;
        log.warn("the component the short name '{s}' resolves to, '{s}', is not registered", .{ name_s, target.? });
        return R.code(error.NotFound);
    }
    if (direct) list.print(" and '{s}'", .{name_s}) catch {};
    log.warn("component name '{s}' is ambiguous between {s}; write the full name", .{ name_s, list.buffered() });
    return R.code(error.InvalidArgument);
}

/// The destroy function of the handle. After it returns the registry buffer and the state are
/// freed; the ecs is untouched.
fn destroy(self_in: ?*abi_component_registry.c.ke_component_registry) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.apply_registry) |reg| heap.gpa.free(reg[0..s.apply_capacity]);
    for (s.aliases.items) |a| {
        heap.gpa.free(a.alias);
        heap.gpa.free(a.name);
    }
    s.aliases.deinit(heap.gpa);
    heap.gpa.destroy(s);
}

fn registerBuiltin(
    registry: *abi_component_registry.c.ke_component_registry,
    e: *abi_ecs.c.ke_ecs,
    name: [*c]const u8,
    comptime T: type,
    apply_fn: abi_component_registry.c.ke_component_apply_fn,
    fields: ?[*]const abi_ecs.c.ke_component_field,
    field_count: u32,
) R.Error!void {
    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_params{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = fields orelse null, .field_count = field_count }, &cid));
    if (fields) |f| try R.check(registry.register_component_fields.?(registry, cid, f, field_count));
    if (apply_fn != null) try R.check(registry.register_component_apply.?(registry, cid, apply_fn, null));
}

/// Factory. Writes a handle whose `ref` is the registry and whose destroy is `destroy`, after
/// registering the transform, 2D transform and world transform components on the ecs. A null ecs
/// or out-parameter fails as an invalid argument; a failed allocation fails as out of memory; a
/// refused builtin registration fails with the ecs's code. Each leaves the handle zeroed.
export fn ke_component_registry_create(
    ecs_in: ?*abi_ecs.c.ke_ecs,
    out_registry: ?*abi_component_registry.c.ke_component_registry_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_registry orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_component_registry.c.ke_component_registry_handle);
    const e = ecs_in orelse return R.code(error.InvalidArgument);

    const state = heap.gpa.create(State) catch |err| return R.code(err);
    state.* = .{ .api = std.mem.zeroes(abi_component_registry.c.ke_component_registry), .ecs = e };
    const registry = &state.api;
    registry.handle = state;
    registry.register_component_fields = registerComponentFields;
    registry.get_component_fields = getComponentFields;
    registry.register_component_apply = registerComponentApply;
    registry.get_component_apply = getComponentApply;
    registry.register_component_alias = registerComponentAlias;
    registry.resolve_component = resolveComponent;

    registerBuiltins(registry, e) catch |err| {
        destroy(registry);
        return R.code(err);
    };

    out.* = .{ .ref = registry, .destroy = destroy };
    return R.ok;
}

fn registerBuiltins(registry: *abi_component_registry.c.ke_component_registry, e: *abi_ecs.c.ke_ecs) R.Error!void {
    try registerBuiltin(registry, e, abi_spatial_contract.c.KE_COMPONENT_NAME_TRANSFORM, abi_spatial.c.ke_transform_component, null, &abi_spatial_contract.c.ke_transform_component_fields, abi_spatial_contract.c.ke_transform_component_fields.len);
    try registerBuiltin(registry, e, abi_spatial_contract.c.KE_COMPONENT_NAME_TRANSFORM2D, abi_spatial.c.ke_transform2d_component, null, &abi_spatial_contract.c.ke_transform2d_component_fields, abi_spatial_contract.c.ke_transform2d_component_fields.len);
    try registerBuiltin(registry, e, abi_spatial_contract.c.KE_COMPONENT_NAME_WORLD_TRANSFORM, abi_spatial.c.ke_world_transform_component, null, null, 0);
}

const testing = std.testing;

fn testRegistry(ecs: ?*abi_ecs.c.ke_ecs) abi_component_registry.c.ke_component_registry_handle {
    var h = std.mem.zeroes(abi_component_registry.c.ke_component_registry_handle);
    _ = ke_component_registry_create(ecs, &h);
    return h;
}

const StubEcs = struct {
    vtable: abi_ecs.c.ke_ecs,
    next_cid: abi_asset_resolver.c.ke_component_id,
    next_entity: abi_asset_resolver.c.ke_entity,
    names: [16][32]u8,
};

fn stubEcsOf(self: ?*abi_ecs.c.ke_ecs) *StubEcs {
    return @ptrCast(@alignCast(self.?.handle));
}

fn stubComponentLookup(
    self: ?*abi_ecs.c.ke_ecs,
    name: [*c]const u8,
    out_meta: [*c]abi_ecs.c.ke_component_meta,
) callconv(.c) bool {
    const s = stubEcsOf(self);
    for (s.names[0..s.next_cid], 1..) |*n, cid| {
        if (!std.mem.eql(u8, std.mem.sliceTo(n, 0), std.mem.span(name))) continue;
        out_meta.* = std.mem.zeroes(abi_ecs.c.ke_component_meta);
        out_meta.*.cid = @intCast(cid);
        return true;
    }
    return false;
}

fn stubComponentRegister(
    self: ?*abi_ecs.c.ke_ecs,
    params: [*c]const abi_ecs.c.ke_component_params,
    out_cid: [*c]abi_asset_resolver.c.ke_component_id,
) callconv(.c) abi_result.c.ke_result {
    const s = stubEcsOf(self);
    const span = std.mem.span(params.*.name.?);
    @memcpy(s.names[s.next_cid][0..span.len], span);
    s.next_cid += 1;
    return answer(out_cid, s.next_cid);
}

fn answer(out_cid: [*c]abi_asset_resolver.c.ke_component_id, cid: abi_asset_resolver.c.ke_component_id) abi_result.c.ke_result {
    out_cid.* = cid;
    return if (cid == 0) R.code(error.InvalidArgument) else R.ok;
}

fn stubEcsInit(s: *StubEcs) void {
    s.* = std.mem.zeroes(StubEcs);
    s.vtable.handle = s;
    s.vtable.component_lookup = stubComponentLookup;
    s.vtable.component_register = stubComponentRegister;
}

test "a registry registers the three transforms on its ecs and refuses a missing ecs" {
    var ecs: StubEcs = undefined;
    stubEcsInit(&ecs);
    const h = testRegistry(&ecs.vtable);
    try testing.expect(h.ref != null);
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_component_id, 3), ecs.next_cid);
    var count: u32 = 0;
    try testing.expect(h.ref.?.get_component_fields.?(h.ref, 1, &count) != null);
    h.destroy.?(h.ref);

    try testing.expect(testRegistry(null).ref == null);
    try heap.expectNoLeaks();
}

fn aliasRegistry(ecs: *StubEcs) abi_component_registry.c.ke_component_registry_handle {
    stubEcsInit(ecs);
    return testRegistry(&ecs.vtable);
}

test "a short name a single component answers to resolves to it, and the full name still does" {
    var ecs: StubEcs = undefined;
    const h = aliasRegistry(&ecs);
    const w: *abi_component_registry.c.ke_component_registry = h.ref.?;
    var paddle: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.c.ke_component_params{ .name = "pong.paddle", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &paddle));
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "paddle", "pong.paddle"));
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "paddle", "pong.paddle"));

    var meta: abi_ecs.c.ke_component_meta = undefined;
    try testing.expectEqual(R.ok, w.resolve_component.?(w, "paddle", &meta));
    try testing.expectEqual(paddle, meta.cid);
    try testing.expectEqual(R.ok, w.resolve_component.?(w, "pong.paddle", &meta));
    try testing.expectEqual(paddle, meta.cid);

    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

test "a short name two components answer to is refused as an invalid argument" {
    var ecs: StubEcs = undefined;
    const h = aliasRegistry(&ecs);
    const w: *abi_component_registry.c.ke_component_registry = h.ref.?;
    {
        var ignored: abi_asset_resolver.c.ke_component_id = 0;
        try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.c.ke_component_params{ .name = "pong.paddle", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &ignored));
    }
    {
        var ignored: abi_asset_resolver.c.ke_component_id = 0;
        try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.c.ke_component_params{ .name = "tennis.paddle", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &ignored));
    }
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "paddle", "pong.paddle"));
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "paddle", "tennis.paddle"));

    var meta: abi_ecs.c.ke_component_meta = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), w.resolve_component.?(w, "paddle", &meta));

    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

test "a short name that is also a registered component name is refused" {
    var ecs: StubEcs = undefined;
    const h = aliasRegistry(&ecs);
    const w: *abi_component_registry.c.ke_component_registry = h.ref.?;
    {
        var ignored: abi_asset_resolver.c.ke_component_id = 0;
        try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.c.ke_component_params{ .name = "marker", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &ignored));
    }
    {
        var ignored: abi_asset_resolver.c.ke_component_id = 0;
        try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.c.ke_component_params{ .name = "game.marker", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &ignored));
    }
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "marker", "game.marker"));

    var meta: abi_ecs.c.ke_component_meta = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), w.resolve_component.?(w, "marker", &meta));
    try testing.expectEqual(R.code(error.NotFound), w.resolve_component.?(w, "absent", &meta));

    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

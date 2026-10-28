//! The world: the handle that carries the ecs, runtime and scene tree the framework works on, and
//! the registry of how a scene fills each component.

const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.framework);

const apply = @import("components_apply.zig");

const apply_initial_capacity: u32 = 16;

/// One entry per component id. The apply half (`fn_ptr`, `ctx`) and the fields half (`fields`,
/// `field_count`) are written by separate registration slots, so either half may stay unset.
const ApplyEntry = struct {
    cid: abi_ecs.ke_component_id,
    fn_ptr: abi_framework.ke_component_apply_fn,
    ctx: ?*anyopaque,
    fields: ?[*]const abi_ecs.ke_component_field,
    field_count: u32,
};

/// One short name a scene may write for a component, and the full name it stands for. Both are
/// copies the world owns.
const Alias = struct {
    alias: [:0]u8,
    name: [:0]u8,
};

/// The state of one world, held by `Block`. The pointers it holds are borrowed from the creation
/// params and never freed. `apply_registry` stays null until the first registration, and
/// `apply_capacity` is the length of the buffer it points to, which is what `worldDestroy` frees.
const State = struct {
    ecs: ?*abi_ecs.ke_ecs,
    runtime: ?*abi_runtime.ke_runtime,
    scene_tree: ?*abi_framework.ke_scene_tree,
    signal_bus: ?*abi_framework.ke_signal_bus,

    apply_registry: ?[*]ApplyEntry,
    apply_count: u32,
    apply_capacity: u32,

    aliases: std.ArrayList(Alias),
};

/// The single allocation of a world: the state and the vtable. The `ref` of the handle returned by
/// `ke_world_create` points at the `world` field, and `handle` of that vtable points at `state`,
/// so the destroy function reaches both from either.
const Block = struct {
    state: State,
    world: abi_framework.ke_world,
};

fn stateOf(self: *abi_framework.ke_world) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// Returns the signal bus given at creation. The world only borrows it, and null if none was given.
pub fn signalBusOf(self: *abi_framework.ke_world) ?*abi_framework.ke_signal_bus {
    return stateOf(self).signal_bus;
}

/// Slot `ecs`. Returns the ecs given at creation, or null for a null world.
fn worldEcs(self_in: ?*abi_framework.ke_world) callconv(.c) ?*abi_ecs.ke_ecs {
    const self = self_in orelse return null;
    return stateOf(self).ecs;
}

/// Slot `runtime`. Returns the runtime given at creation, or null for a null world.
fn worldRuntime(self_in: ?*abi_framework.ke_world) callconv(.c) ?*abi_runtime.ke_runtime {
    const self = self_in orelse return null;
    return stateOf(self).runtime;
}

/// Slot `scene_tree`. Returns the scene tree given at creation, null when none was given or for a
/// null world.
fn worldSceneTree(self_in: ?*abi_framework.ke_world) callconv(.c) ?*abi_framework.ke_scene_tree {
    const self = self_in orelse return null;
    return stateOf(self).scene_tree;
}

/// Returns the entry for the given component id, appending an empty one when there is none. Both
/// registration slots go through it. Appending can replace the whole buffer, so an entry pointer
/// kept across a later call is not valid after that call. On an allocation failure the registry
/// is unchanged.
fn entryFor(s: *State, cid: abi_ecs.ke_component_id) error{OutOfMemory}!*ApplyEntry {
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
/// a null world or callback, and as out of memory when the registry cannot grow.
fn worldRegisterComponentApply(
    self_in: ?*abi_framework.ke_world,
    cid: abi_ecs.ke_component_id,
    apply_fn: abi_framework.ke_component_apply_fn,
    ctx: ?*anyopaque,
) callconv(.c) abi_result.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or apply_fn == null) return R.code(error.InvalidArgument);
    const entry = entryFor(stateOf(self), cid) catch |err| return R.code(err);
    entry.fn_ptr = apply_fn;
    entry.ctx = ctx;
    return R.ok;
}

/// Slot `register_component_fields`. Sets the field table of a component id, leaving its callback
/// alone; the table is borrowed, not copied. Fails as an invalid argument for a null world or
/// table or a zero count, and as out of memory when the registry cannot grow.
fn worldRegisterComponentFields(
    self_in: ?*abi_framework.ke_world,
    cid: abi_ecs.ke_component_id,
    fields: [*c]const abi_ecs.ke_component_field,
    field_count: u32,
) callconv(.c) abi_result.ke_result {
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
fn worldGetComponentFields(
    self_in: ?*abi_framework.ke_world,
    cid: abi_ecs.ke_component_id,
    out_count: [*c]u32,
) callconv(.c) [*c]const abi_ecs.ke_component_field {
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
fn worldGetComponentApply(
    self_in: ?*abi_framework.ke_world,
    cid: abi_ecs.ke_component_id,
    out_ctx: [*c]?*anyopaque,
) callconv(.c) abi_framework.ke_component_apply_fn {
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
/// argument for a null world, alias or name, and as out of memory when a copy cannot be made.
fn worldRegisterComponentAlias(
    self_in: ?*abi_framework.ke_world,
    alias: [*c]const u8,
    name: [*c]const u8,
) callconv(.c) abi_result.ke_result {
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
fn worldResolveComponent(
    self_in: ?*abi_framework.ke_world,
    name: [*c]const u8,
    out_meta: [*c]abi_ecs.ke_component_meta,
) callconv(.c) abi_result.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or name == null or out_meta == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const e = s.ecs orelse return R.code(error.InvalidArgument);
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

/// The destroy function of the handle. After it returns the registry buffer and the block are
/// freed; the ecs, runtime and other borrowed objects are untouched.
fn worldDestroy(self_in: ?*abi_framework.ke_world) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.apply_registry) |reg| heap.gpa.free(reg[0..s.apply_capacity]);
    for (s.aliases.items) |a| {
        heap.gpa.free(a.alias);
        heap.gpa.free(a.name);
    }
    s.aliases.deinit(heap.gpa);
    heap.gpa.destroy(@as(*Block, @fieldParentPtr("state", s)));
}

/// Called by `ke_world_create` once for each builtin component. A refusal of the ecs fails with
/// its code; the world's own registrations cannot fail on a block just created except for lack of
/// memory.
fn registerBuiltin(
    world: *abi_framework.ke_world,
    e: *abi_ecs.ke_ecs,
    name: [*c]const u8,
    comptime T: type,
    apply_fn: abi_framework.ke_component_apply_fn,
    fields: ?[*]const abi_ecs.ke_component_field,
    field_count: u32,
) R.Error!void {
    var cid: abi_ecs.ke_component_id = 0;
    try R.check(e.component_register.?(e, &abi_ecs.ke_component_params{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = fields orelse null, .field_count = field_count }, &cid));
    if (fields) |f| try R.check(world.register_component_fields.?(world, cid, f, field_count));
    if (apply_fn != null) try R.check(world.register_component_apply.?(world, cid, apply_fn, null));
}

/// Factory. Writes a handle whose `ref` is the world and whose destroy is `worldDestroy`, after
/// registering the transform, 2D transform and world transform components on the ecs. A null
/// params pointer or out-parameter, or a missing ecs or runtime, fails as an invalid argument; a
/// failed allocation fails as out of memory; a refused builtin registration fails with the ecs's
/// code. Each leaves the handle zeroed.
export fn ke_world_create(
    params_in: ?*const abi_framework.ke_world_params,
    out_world: ?*abi_framework.ke_world_handle,
) callconv(.c) abi_result.ke_result {
    const out = out_world orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_framework.ke_world_handle);
    const params = params_in orelse return R.code(error.InvalidArgument);
    if (params.ecs == null or params.runtime == null) return R.code(error.InvalidArgument);

    const block = heap.gpa.create(Block) catch |err| return R.code(err);
    block.* = std.mem.zeroes(Block);
    block.state.aliases = .empty;

    const state = &block.state;
    const world = &block.world;

    state.ecs = params.ecs;
    state.runtime = params.runtime;
    state.scene_tree = params.scene_tree;
    state.signal_bus = params.signal_bus;

    world.handle = state;
    world.ecs = worldEcs;
    world.runtime = worldRuntime;
    world.scene_tree = worldSceneTree;
    world.register_component_fields = worldRegisterComponentFields;
    world.get_component_fields = worldGetComponentFields;
    world.register_component_apply = worldRegisterComponentApply;
    world.get_component_apply = worldGetComponentApply;
    world.register_component_alias = worldRegisterComponentAlias;
    world.resolve_component = worldResolveComponent;

    const e = params.ecs.?;
    registerBuiltins(world, e) catch |err| {
        worldDestroy(world);
        return R.code(err);
    };

    out.* = .{ .ref = world, .destroy = worldDestroy };
    return R.ok;
}

fn registerBuiltins(world: *abi_framework.ke_world, e: *abi_ecs.ke_ecs) R.Error!void {
    try registerBuiltin(world, e, abi_spatial.KE_COMPONENT_NAME_TRANSFORM, abi_spatial.ke_transform_component, apply.ke_framework_apply_transform, &abi_spatial.ke_transform_component_fields, abi_spatial.ke_transform_component_fields.len);
    try registerBuiltin(world, e, abi_spatial.KE_COMPONENT_NAME_TRANSFORM2D, abi_spatial.ke_transform2d_component, apply.ke_framework_apply_transform2d, &abi_spatial.ke_transform2d_component_fields, abi_spatial.ke_transform2d_component_fields.len);
    try registerBuiltin(world, e, abi_spatial.KE_COMPONENT_NAME_WORLD_TRANSFORM, abi_spatial.ke_world_transform_component, null, null, 0);
}

const testing = std.testing;

fn testWorld(params: *const abi_framework.ke_world_params) abi_framework.ke_world_handle {
    var h = std.mem.zeroes(abi_framework.ke_world_handle);
    _ = ke_world_create(params, &h);
    return h;
}

const StubEcs = struct {
    vtable: abi_ecs.ke_ecs,
    next_cid: abi_ecs.ke_component_id,
    next_entity: abi_ecs.ke_entity,
    names: [16][32]u8,
};

fn stubEcsOf(self: ?*abi_ecs.ke_ecs) *StubEcs {
    return @ptrCast(@alignCast(self.?.handle));
}

fn stubComponentLookup(
    self: ?*abi_ecs.ke_ecs,
    name: [*c]const u8,
    out_meta: [*c]abi_ecs.ke_component_meta,
) callconv(.c) bool {
    const s = stubEcsOf(self);
    for (s.names[0..s.next_cid], 1..) |*n, cid| {
        if (!std.mem.eql(u8, std.mem.sliceTo(n, 0), std.mem.span(name))) continue;
        out_meta.* = std.mem.zeroes(abi_ecs.ke_component_meta);
        out_meta.*.cid = @intCast(cid);
        return true;
    }
    return false;
}

fn stubComponentRegister(
    self: ?*abi_ecs.ke_ecs,
    params: [*c]const abi_ecs.ke_component_params,
    out_cid: [*c]abi_ecs.ke_component_id,
) callconv(.c) abi_result.ke_result {
    const s = stubEcsOf(self);
    const span = std.mem.span(params.*.name.?);
    @memcpy(s.names[s.next_cid][0..span.len], span);
    s.next_cid += 1;
    return answer(out_cid, s.next_cid);
}

fn answer(out_cid: [*c]abi_ecs.ke_component_id, cid: abi_ecs.ke_component_id) abi_result.ke_result {
    out_cid.* = cid;
    return if (cid == 0) R.code(error.InvalidArgument) else R.ok;
}

fn stubEntityCreate(self: ?*abi_ecs.ke_ecs, out_entity: [*c]abi_ecs.ke_entity) callconv(.c) abi_result.ke_result {
    const s = stubEcsOf(self);
    s.next_entity += 1;
    out_entity.* = s.next_entity;
    return R.ok;
}

fn worldEntity(ecs: *abi_ecs.ke_ecs) R.Error!abi_ecs.ke_entity {
    var entity: abi_ecs.ke_entity = abi_ecs.KE_ENTITY_INVALID;
    try R.check(ecs.entity_create.?(ecs, &entity));
    return entity;
}

fn stubEcsInit(s: *StubEcs) void {
    s.* = std.mem.zeroes(StubEcs);
    s.vtable.handle = s;
    s.vtable.component_lookup = stubComponentLookup;
    s.vtable.component_register = stubComponentRegister;
    s.vtable.entity_create = stubEntityCreate;
}

test "a world hands back the ecs and runtime it was built with, and no tree it never got" {
    var ecs: StubEcs = undefined;
    stubEcsInit(&ecs);
    var runtime = std.mem.zeroes(abi_runtime.ke_runtime);

    var params = std.mem.zeroes(abi_framework.ke_world_params);
    params.ecs = &ecs.vtable;
    params.runtime = &runtime;

    const h = testWorld(&params);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    const w: *abi_framework.ke_world = h.ref.?;
    try testing.expectEqual(@as(?*abi_ecs.ke_ecs, &ecs.vtable), w.*.ecs.?(w));
    try testing.expectEqual(@as(?*abi_runtime.ke_runtime, &runtime), w.*.runtime.?(w));
    try testing.expect(w.*.scene_tree.?(w) == null);

    const e = w.*.ecs.?(w).?;
    try testing.expect((try worldEntity(e)) != abi_ecs.KE_ENTITY_INVALID);
}

test "two worlds never share the ecs, and destroying one leaves the other alive" {
    var ecs_a: StubEcs = undefined;
    var ecs_b: StubEcs = undefined;
    stubEcsInit(&ecs_a);
    stubEcsInit(&ecs_b);
    var runtime = std.mem.zeroes(abi_runtime.ke_runtime);

    var pa = std.mem.zeroes(abi_framework.ke_world_params);
    pa.ecs = &ecs_a.vtable;
    pa.runtime = &runtime;
    var pb = std.mem.zeroes(abi_framework.ke_world_params);
    pb.ecs = &ecs_b.vtable;
    pb.runtime = &runtime;

    const ha = testWorld(&pa);
    const hb = testWorld(&pb);
    try testing.expect(ha.ref != null);
    try testing.expect(hb.ref != null);

    const wa = ha.ref.?;
    const wb = hb.ref.?;
    const ea = wa.*.ecs.?(wa).?;
    const eb = wb.*.ecs.?(wb).?;
    try testing.expect(ea != eb);

    const a = (try worldEntity(ea));
    const b = (try worldEntity(eb));
    try testing.expect(a != abi_ecs.KE_ENTITY_INVALID);
    try testing.expect(b != abi_ecs.KE_ENTITY_INVALID);

    ha.destroy.?(ha.ref);

    const b2 = (try worldEntity(eb));
    try testing.expect(b2 != abi_ecs.KE_ENTITY_INVALID);
    try testing.expect(b2 != b);

    hb.destroy.?(hb.ref);
}

test "creating and destroying a world leaves no block allocated" {
    var ecs: StubEcs = undefined;
    stubEcsInit(&ecs);
    var runtime = std.mem.zeroes(abi_runtime.ke_runtime);

    var params = std.mem.zeroes(abi_framework.ke_world_params);
    params.ecs = &ecs.vtable;
    params.runtime = &runtime;

    const h = testWorld(&params);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

fn aliasWorld(ecs: *StubEcs, runtime: *abi_runtime.ke_runtime) abi_framework.ke_world_handle {
    stubEcsInit(ecs);
    runtime.* = std.mem.zeroes(abi_runtime.ke_runtime);
    var params = std.mem.zeroes(abi_framework.ke_world_params);
    params.ecs = &ecs.vtable;
    params.runtime = runtime;
    return testWorld(&params);
}

test "a short name a single component answers to resolves to it, and the full name still does" {
    var ecs: StubEcs = undefined;
    var runtime: abi_runtime.ke_runtime = undefined;
    const h = aliasWorld(&ecs, &runtime);
    const w: *abi_framework.ke_world = h.ref.?;
    var paddle: abi_ecs.ke_component_id = 0;
    try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.ke_component_params{ .name = "pong.paddle", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &paddle));
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "paddle", "pong.paddle"));
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "paddle", "pong.paddle"));

    var meta: abi_ecs.ke_component_meta = undefined;
    try testing.expectEqual(R.ok, w.resolve_component.?(w, "paddle", &meta));
    try testing.expectEqual(paddle, meta.cid);
    try testing.expectEqual(R.ok, w.resolve_component.?(w, "pong.paddle", &meta));
    try testing.expectEqual(paddle, meta.cid);

    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

test "a short name two components answer to is refused as an invalid argument" {
    var ecs: StubEcs = undefined;
    var runtime: abi_runtime.ke_runtime = undefined;
    const h = aliasWorld(&ecs, &runtime);
    const w: *abi_framework.ke_world = h.ref.?;
    {
        var ignored: abi_ecs.ke_component_id = 0;
        try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.ke_component_params{ .name = "pong.paddle", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &ignored));
    }
    {
        var ignored: abi_ecs.ke_component_id = 0;
        try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.ke_component_params{ .name = "tennis.paddle", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &ignored));
    }
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "paddle", "pong.paddle"));
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "paddle", "tennis.paddle"));

    var meta: abi_ecs.ke_component_meta = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), w.resolve_component.?(w, "paddle", &meta));

    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

test "a short name that is also a registered component name is refused" {
    var ecs: StubEcs = undefined;
    var runtime: abi_runtime.ke_runtime = undefined;
    const h = aliasWorld(&ecs, &runtime);
    const w: *abi_framework.ke_world = h.ref.?;
    {
        var ignored: abi_ecs.ke_component_id = 0;
        try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.ke_component_params{ .name = "marker", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &ignored));
    }
    {
        var ignored: abi_ecs.ke_component_id = 0;
        try R.check(ecs.vtable.component_register.?(&ecs.vtable, &abi_ecs.ke_component_params{ .name = "game.marker", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &ignored));
    }
    try testing.expectEqual(R.ok, w.register_component_alias.?(w, "marker", "game.marker"));

    var meta: abi_ecs.ke_component_meta = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), w.resolve_component.?(w, "marker", &meta));
    try testing.expectEqual(R.code(error.NotFound), w.resolve_component.?(w, "absent", &meta));

    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

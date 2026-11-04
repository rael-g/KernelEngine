//! The script host: the record of which entity a script instance is bound to, and the lookups a
//! script makes from an entity into the scene around it.

const abi_framework_components = @import("abi_framework_components");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_script_host = @import("abi_script_host");
const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_framework_factory = @import("abi_framework_factory");
const abi_result = @import("abi_result");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.framework);

const default_max_types = 64;

/// One record per registered name, kept in `State.types` for the life of the host. `entities` lists
/// the bound entities of this type, and a binding's `slot` is an index into that list. `tag` is the
/// component every bound entity of the type carries beside its binding, so a query can match the
/// instances of one type.
const ScriptType = struct {
    name: []u8,
    components: []abi_asset_resolver.c.ke_component_id,
    reach: abi_script_host.c.ke_script_reach,
    tag: abi_asset_resolver.c.ke_component_id,

    entities: std.ArrayList(abi_asset_resolver.c.ke_entity),
};

/// The component stored in the ecs for each bound entity. `slot` is the index of the entity in its
/// type's `entities` list and is rewritten whenever a swap-removal moves that entity. `type_id` is
/// `KE_SCRIPT_TYPE_NONE` while an unbind is removing the component. `instance` is opaque: it is
/// copied in and out and never dereferenced.
const Binding = extern struct {
    type_id: abi_script_host.c.ke_script_type_id,
    instance: ?*anyopaque,

    slot: u32,
};

const binding_component = "script_instance";
const tag_prefix = "script_type:";
const tag_group_component = "script_type";

/// Allocated by `ke_script_host_create` and freed by `destroy`. Only the first `type_count`
/// elements of `types` hold records; the rest of the table is uninitialised.
///
/// The records of a host live in two places that point at each other. `types` holds one
/// `ScriptType` per registered name, each with the list of entities bound to that type, and a
/// type id is the index of its record plus one. The ecs holds the `Binding` component of every
/// bound entity, which names the type, carries the instance pointer untouched and records the
/// entity's index in its type's list. Binding goes through `bindNow` and unbinding through
/// `unbindNow`, whether the call is immediate or recorded. Nothing here locks, so a host belongs
/// to one thread at a time except for the recorded forms.
const State = struct {
    api: abi_script_host.c.ke_script_host,
    ecs: *abi_ecs.c.ke_ecs,
    hierarchy_cid: abi_asset_resolver.c.ke_component_id,
    name_cid: abi_asset_resolver.c.ke_component_id,

    binding_cid: abi_asset_resolver.c.ke_component_id,
    tag_group_cid: abi_asset_resolver.c.ke_component_id,

    types: []ScriptType,
    type_count: u32,
    aliases: std.ArrayList(Alias) = .empty,
};

/// One short name a scene may write for a type, a copy the host owns.
const Alias = struct {
    alias: [:0]u8,
    type_id: abi_script_host.c.ke_script_type_id,
};

/// Logs `msg` and returns the code of `err`, for a failure whose reason the code does not carry.
fn failed(err: R.Error, comptime msg: []const u8) abi_result.c.ke_result {
    log.warn(msg, .{});
    return R.code(err);
}

fn stateOf(self: *abi_script_host.c.ke_script_host) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn orDefault(v: u32, d: u32) u32 {
    return if (v == 0) d else v;
}

fn typeAt(s: *State, id: abi_script_host.c.ke_script_type_id) ?*ScriptType {
    if (id == abi_script_host.c.KE_SCRIPT_TYPE_NONE or id > s.type_count) return null;
    return &s.types[id - 1];
}

fn bindingOf(s: *State, entity: abi_asset_resolver.c.ke_entity) ?*Binding {
    const raw = s.ecs.component_get.?(s.ecs, entity, s.binding_cid) orelse return null;
    const b: *Binding = @ptrCast(@alignCast(raw));
    return if (b.type_id == abi_script_host.c.KE_SCRIPT_TYPE_NONE) null else b;
}

fn getHierarchy(s: *State, e: abi_asset_resolver.c.ke_entity) ?*abi_framework_components.c.ke_hierarchy_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.hierarchy_cid)));
}

fn getName(s: *State, e: abi_asset_resolver.c.ke_entity) []const u8 {
    const raw = s.ecs.component_get.?(s.ecs, e, s.name_cid) orelse return &[_]u8{};
    const comp: *const abi_framework_components.c.ke_name_component = @ptrCast(@alignCast(raw));
    return std.mem.sliceTo(&comp.name, 0);
}

fn matches(s: *State, entity: abi_asset_resolver.c.ke_entity, types: []const abi_script_host.c.ke_script_type_id, wanted: []const u8) bool {
    const b = bindingOf(s, entity) orelse return false;
    if (std.mem.indexOfScalar(abi_script_host.c.ke_script_type_id, types, b.type_id) == null) return false;
    if (wanted.len == 0) return true;
    return std.mem.eql(u8, getName(s, entity), wanted);
}

/// Slot `register_type`. Registering a name again with the same reach and components returns the
/// id the first registration got. The same name with any other description fails with
/// already-exists and leaves the table unchanged. A new name fails with out-of-memory when the
/// table is full. A null host, name or `out_id`, an empty name, or a component count without
/// components fails as an invalid argument. A tag the ecs refuses fails with its code.
fn registerType(
    self_in: ?*abi_script_host.c.ke_script_host,
    name_in: [*c]const u8,
    components_in: [*c]const abi_asset_resolver.c.ke_component_id,
    component_count: u32,
    reach: abi_script_host.c.ke_script_reach,
    out_id: [*c]abi_script_host.c.ke_script_type_id,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (name_in == null or out_id == null) {
        return failed(error.InvalidArgument, "type name and out_id are required");
    }
    const s = stateOf(self);
    const name = std.mem.span(name_in);
    if (name.len == 0) {
        return failed(error.InvalidArgument, "script type name is empty");
    }
    if (component_count > 0 and components_in == null) {
        return failed(error.InvalidArgument, "component count is non-zero but no components were given");
    }

    for (s.types[0..s.type_count], 0..) |*t, i| {
        if (!std.mem.eql(u8, t.name, name)) continue;
        if (t.components.len != component_count or t.reach != reach) {
            return failed(error.AlreadyExists, "script type already registered with a different description");
        }
        for (0..component_count) |k| {
            if (t.components[k] == components_in[k]) continue;
            return failed(error.AlreadyExists, "script type already registered with different components");
        }
        out_id.* = @intCast(i + 1);
        return R.ok;
    }

    if (s.type_count == s.types.len) {
        return failed(error.OutOfMemory, "script type table is full");
    }

    const owned_name = heap.gpa.dupe(u8, name) catch {
        return failed(error.OutOfMemory, "script type name allocation failed");
    };
    const owned_components = heap.gpa.dupe(abi_asset_resolver.c.ke_component_id, if (component_count > 0) components_in[0..component_count] else &.{}) catch {
        heap.gpa.free(owned_name);
        return failed(error.OutOfMemory, "script type component list allocation failed");
    };
    const tag_name = std.fmt.allocPrintSentinel(heap.gpa, "{s}{s}", .{ tag_prefix, name }, 0) catch {
        heap.gpa.free(owned_name);
        heap.gpa.free(owned_components);
        return failed(error.OutOfMemory, "script type tag name allocation failed");
    };
    defer heap.gpa.free(tag_name);
    var tag: abi_asset_resolver.c.ke_component_id = 0;
    const made = s.ecs.component_register.?(s.ecs, &abi_ecs.c.ke_component_params{ .name = tag_name.ptr, .size = 0, .alignment = 0, .fields = null, .field_count = 0 }, &tag);
    if (made != abi_result.c.KE_OK) {
        heap.gpa.free(owned_name);
        heap.gpa.free(owned_components);
        return made;
    }
    const t = ScriptType{
        .name = owned_name,
        .components = owned_components,
        .reach = reach,
        .tag = tag,
        .entities = .empty,
    };

    s.types[s.type_count] = t;
    s.type_count += 1;
    out_id.* = s.type_count;
    return R.ok;
}

/// Slot `type_lookup`. Writes the id registered under the name and returns true; an unknown name
/// returns false without an error.
fn typeLookup(
    self_in: ?*abi_script_host.c.ke_script_host,
    name_in: [*c]const u8,
    out_id: [*c]abi_script_host.c.ke_script_type_id,
) callconv(.c) bool {
    const self = self_in orelse return false;
    if (name_in == null or out_id == null) return false;
    const s = stateOf(self);
    const name = std.mem.span(name_in);
    for (s.types[0..s.type_count], 0..) |*t, i| {
        if (!std.mem.eql(u8, t.name, name)) continue;
        out_id.* = @intCast(i + 1);
        return true;
    }
    return false;
}

/// Slot `register_type_alias`. Records the pair unless it is already recorded; two pairs with one
/// alias are kept both, which is what makes the alias ambiguous.
fn registerTypeAlias(
    self_in: ?*abi_script_host.c.ke_script_host,
    alias_in: [*c]const u8,
    type_id: abi_script_host.c.ke_script_type_id,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (alias_in == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const alias = std.mem.span(alias_in);
    if (alias.len == 0 or typeAt(s, type_id) == null) return R.code(error.InvalidArgument);
    for (s.aliases.items) |a| {
        if (a.type_id == type_id and std.mem.eql(u8, a.alias, alias)) return R.ok;
    }
    const copy = heap.gpa.dupeZ(u8, alias) catch |err| return R.code(err);
    s.aliases.append(heap.gpa, .{ .alias = copy, .type_id = type_id }) catch |err| {
        heap.gpa.free(copy);
        return R.code(err);
    };
    return R.ok;
}

/// Slot `type_resolve`. A registered name wins when no alias shares it; an alias with a single
/// type, and no type registered under the alias itself, resolves to that type.
fn typeResolve(
    self_in: ?*abi_script_host.c.ke_script_host,
    name_in: [*c]const u8,
    out_type: [*c]abi_script_host.c.ke_script_type_id,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (name_in == null or out_type == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const name = std.mem.span(name_in);

    var direct: abi_script_host.c.ke_script_type_id = abi_script_host.c.KE_SCRIPT_TYPE_NONE;
    _ = typeLookup(self, name_in, &direct);

    var target: abi_script_host.c.ke_script_type_id = abi_script_host.c.KE_SCRIPT_TYPE_NONE;
    var candidates: u32 = 0;
    var buf: [256]u8 = undefined;
    var list = std.Io.Writer.fixed(&buf);
    for (s.aliases.items) |a| {
        if (!std.mem.eql(u8, a.alias, name)) continue;
        candidates += 1;
        target = a.type_id;
        list.print("{s}'{s}'", .{ if (candidates > 1) " and " else "", s.types[a.type_id - 1].name }) catch {};
    }

    if (candidates == 0) {
        if (direct != abi_script_host.c.KE_SCRIPT_TYPE_NONE) {
            out_type.* = direct;
            return R.ok;
        }
        log.warn("no node type is registered as '{s}'", .{name});
        return R.code(error.NotFound);
    }
    if (candidates == 1 and direct == abi_script_host.c.KE_SCRIPT_TYPE_NONE) {
        out_type.* = target;
        return R.ok;
    }
    if (direct != abi_script_host.c.KE_SCRIPT_TYPE_NONE) list.print(" and '{s}'", .{name}) catch {};
    log.warn("node type name '{s}' is ambiguous between {s}; write the qualified name", .{ name, list.buffered() });
    return R.code(error.InvalidArgument);
}

/// Slot `type_components`. The returned pointer aims into the record itself, so it stays valid
/// until `destroy`. An id that is not registered returns null with the count written as zero.
fn typeComponents(
    self_in: ?*abi_script_host.c.ke_script_host,
    type_id: abi_script_host.c.ke_script_type_id,
    out_count: [*c]u32,
) callconv(.c) [*c]const abi_asset_resolver.c.ke_component_id {
    const self = self_in orelse return null;
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse {
        if (out_count != null) out_count.* = 0;
        return null;
    };
    if (out_count != null) out_count.* = @intCast(t.components.len);
    return t.components.ptr;
}

/// Slot `type_reach`. An id that is not registered answers the widest reach, so a type the host
/// cannot place is treated as able to touch anything.
fn typeReach(self_in: ?*abi_script_host.c.ke_script_host, type_id: abi_script_host.c.ke_script_type_id) callconv(.c) abi_script_host.c.ke_script_reach {
    const self = self_in orelse return abi_script_host.c.KE_SCRIPT_REACH_ANY;
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse return abi_script_host.c.KE_SCRIPT_REACH_ANY;
    return t.reach;
}

/// Slot `type_tag`. Answers the tag `registerType` registered for the type, or 0 for an id that is
/// not registered.
fn typeTag(self_in: ?*abi_script_host.c.ke_script_host, type_id: abi_script_host.c.ke_script_type_id) callconv(.c) abi_asset_resolver.c.ke_component_id {
    const self = self_in orelse return 0;
    const t = typeAt(stateOf(self), type_id) orelse return 0;
    return t.tag;
}

/// Slot `type_tag_group`. The component registered at creation for the group, 0 for a null host.
fn typeTagGroup(self_in: ?*abi_script_host.c.ke_script_host) callconv(.c) abi_asset_resolver.c.ke_component_id {
    const self = self_in orelse return 0;
    return stateOf(self).tag_group_cid;
}

/// Slot `bind`. Attaches the instance to the entity at once, so it belongs to code that no system
/// body runs beside. Fails as `bindNow` does, and as an invalid argument for a null host.
fn bind(
    self_in: ?*abi_script_host.c.ke_script_host,
    entity: abi_asset_resolver.c.ke_entity,
    type_id: abi_script_host.c.ke_script_type_id,
    instance: ?*anyopaque,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    return R.of(bindNow(stateOf(self), entity, type_id, instance));
}

/// The one place a binding is attached: `bind` calls it directly, and `cbBind` calls it when a
/// recorded bind is applied. Fails as not found for an unregistered type id, as an invalid
/// argument for the invalid entity, as already exists for an entity that carries an instance, and
/// as out of memory when the component or the type's list cannot grow. On failure the entity is
/// left without a binding component, so no caller sees a half-made binding.
fn bindNow(
    s: *State,
    entity: abi_asset_resolver.c.ke_entity,
    type_id: abi_script_host.c.ke_script_type_id,
    instance: ?*anyopaque,
) R.Error!void {
    const t = typeAt(s, type_id) orelse return error.NotFound;
    if (entity == abi_ecs.c.KE_ENTITY_INVALID) return error.InvalidArgument;
    if (bindingOf(s, entity) != null) return error.AlreadyExists;

    var binding: ?*anyopaque = null;
    try R.check(s.ecs.component_add.?(s.ecs, entity, s.binding_cid, &binding));
    errdefer _ = s.ecs.component_remove.?(s.ecs, entity, s.binding_cid);
    try t.entities.append(heap.gpa, entity);
    errdefer _ = t.entities.pop();

    var tagged: ?*anyopaque = null;
    try R.check(s.ecs.component_add.?(s.ecs, entity, t.tag, &tagged));
    errdefer _ = s.ecs.component_remove.?(s.ecs, entity, t.tag);

    const moved = s.ecs.component_get.?(s.ecs, entity, s.binding_cid) orelse return error.OutOfMemory;
    const b: *Binding = @ptrCast(@alignCast(moved));
    b.type_id = type_id;
    b.instance = instance;
    b.slot = @intCast(t.entities.items.len - 1);
}

/// A bind waiting in a command queue. `bindDeferred` hands the queue this record's address and
/// size, and `cbBind` reads it when the queue is applied.
const PendingBind = struct {
    s: *State,
    entity: abi_asset_resolver.c.ke_entity,
    type_id: abi_script_host.c.ke_script_type_id,
    instance: ?*anyopaque,
};

const PendingUnbind = struct {
    s: *State,
    entity: abi_asset_resolver.c.ke_entity,
};

/// Run by the command queue when a recorded bind is applied; a bind that fails there is returned
/// to the flush.
fn cbBind(_: ?*abi_ecs.c.ke_ecs, user: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const p: *const PendingBind = @ptrCast(@alignCast(user.?));
    bindNow(p.s, p.entity, p.type_id, p.instance) catch |err| {
        log.warn("binding the recorded entity {d} failed: {t}", .{ p.entity, err });
        return R.code(err);
    };
    return R.ok;
}

/// Run by the command queue when a recorded unbind is applied; an entity without a binding by then
/// is left alone.
fn cbUnbind(_: ?*abi_ecs.c.ke_ecs, user: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const p: *const PendingUnbind = @ptrCast(@alignCast(user.?));
    unbindNow(p.s, p.entity) catch |err| {
        log.warn("unbinding the recorded entity {d} failed: {t}", .{ p.entity, err });
        return R.code(err);
    };
    return R.ok;
}

/// Slot `bind_deferred`. Checks the type, the entity and the command queue when it is called, but
/// attaches nothing: the bind is recorded to run `cbBind` when the queue is applied, so the host
/// does not change under a system body that is reading `instances`. A null host or queue or the
/// invalid entity fails as an invalid argument, an unregistered type as not found, and a failed
/// recording with the queue's code.
fn bindDeferred(
    self_in: ?*abi_script_host.c.ke_script_host,
    entity: abi_asset_resolver.c.ke_entity,
    type_id: abi_script_host.c.ke_script_type_id,
    instance: ?*anyopaque,
    commands: ?*abi_ecs.c.ke_ecs_commands,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const cmds = commands orelse return R.code(error.InvalidArgument);
    const s = stateOf(self);
    if (typeAt(s, type_id) == null) return R.code(error.NotFound);
    if (entity == abi_ecs.c.KE_ENTITY_INVALID) return R.code(error.InvalidArgument);
    var pending: PendingBind = .{ .s = s, .entity = entity, .type_id = type_id, .instance = instance };
    return cmds.@"defer".?(cmds, cbBind, &pending, @sizeOf(PendingBind));
}

/// Slot `unbind_deferred`. Only the host and the command queue are checked when it is called, and
/// a null one fails as an invalid argument; a failed recording fails with the queue's code. The
/// entity's binding is looked up when the recorded unbind is applied by `cbUnbind`, not now.
fn unbindDeferred(
    self_in: ?*abi_script_host.c.ke_script_host,
    entity: abi_asset_resolver.c.ke_entity,
    commands: ?*abi_ecs.c.ke_ecs_commands,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const cmds = commands orelse return R.code(error.InvalidArgument);
    var pending: PendingUnbind = .{ .s = stateOf(self), .entity = entity };
    return cmds.@"defer".?(cmds, cbUnbind, &pending, @sizeOf(PendingUnbind));
}

/// Slot `unbind`. Removes the entity's binding at once; an entity with none is left alone.
fn unbind(self_in: ?*abi_script_host.c.ke_script_host, entity: abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    return R.of(unbindNow(stateOf(self), entity));
}

/// Removes the entity from its type's list keeping the others in binding order, and rewrites the
/// index of every binding that moved down, so each index keeps naming its entity. An entity with
/// no binding is left untouched.
fn unbindNow(s: *State, entity: abi_asset_resolver.c.ke_entity) R.Error!void {
    const b = bindingOf(s, entity) orelse return;
    const tag = if (typeAt(s, b.type_id)) |t| t.tag else 0;
    if (typeAt(s, b.type_id)) |t| {
        if (b.slot < t.entities.items.len) {
            _ = t.entities.orderedRemove(b.slot);
            for (t.entities.items[b.slot..], b.slot..) |moved, i| {
                if (bindingOf(s, moved)) |other| other.slot = @intCast(i);
            }
        }
    }
    b.type_id = abi_script_host.c.KE_SCRIPT_TYPE_NONE;
    b.instance = null;
    if (tag != 0) try R.check(s.ecs.component_remove.?(s.ecs, entity, tag));
    try R.check(s.ecs.component_remove.?(s.ecs, entity, s.binding_cid));
}

/// Slot `instance_of`. Writes the type and instance bound to the entity and returns true; an
/// entity without a binding returns false.
fn instanceOf(
    self_in: ?*abi_script_host.c.ke_script_host,
    entity: abi_asset_resolver.c.ke_entity,
    out_type: [*c]abi_script_host.c.ke_script_type_id,
    out_instance: [*c]?*anyopaque,
) callconv(.c) bool {
    const self = self_in orelse return false;
    const s = stateOf(self);
    const b = bindingOf(s, entity) orelse return false;
    if (out_type != null) out_type.* = b.type_id;
    if (out_instance != null) out_instance.* = b.instance;
    return true;
}

/// Slot `instance_count`. Returns how many entities are bound to the type, zero for an unknown
/// id.
fn instanceCount(self_in: ?*abi_script_host.c.ke_script_host, type_id: abi_script_host.c.ke_script_type_id) callconv(.c) u32 {
    const self = self_in orelse return 0;
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse return 0;
    return @intCast(t.entities.items.len);
}

/// Slot `instances`. The storage is the type's own list, handed out without a copy. The next bind
/// or unbind of that type may move or reallocate it, so the pointer is valid only until then. An
/// unknown id returns null with the count written as zero.
fn instances(
    self_in: ?*abi_script_host.c.ke_script_host,
    type_id: abi_script_host.c.ke_script_type_id,
    out_count: [*c]u32,
) callconv(.c) [*c]const abi_asset_resolver.c.ke_entity {
    const self = self_in orelse return null;
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse {
        if (out_count != null) out_count.* = 0;
        return null;
    };
    if (out_count != null) out_count.* = @intCast(t.entities.items.len);
    return t.entities.items.ptr;
}

/// Depth-first over the children of the given parent. On a second match it returns true with the
/// first match still held in the out-entity, which the caller reads as ambiguity.
fn descendantOf(s: *State, parent: abi_asset_resolver.c.ke_entity, types: []const abi_script_host.c.ke_script_type_id, wanted: []const u8, found: *abi_asset_resolver.c.ke_entity) bool {
    const h = getHierarchy(s, parent) orelse return false;
    var child = h.first_child;
    while (child != abi_ecs.c.KE_ENTITY_INVALID) {
        if (matches(s, child, types, wanted)) {
            if (found.* != abi_ecs.c.KE_ENTITY_INVALID) return true;
            found.* = child;
        }
        if (descendantOf(s, child, types, wanted, found)) return true;
        child = if (getHierarchy(s, child)) |ch| ch.next_sibling else abi_ecs.c.KE_ENTITY_INVALID;
    }
    return false;
}

fn why(out: [*c]abi_script_host.c.ke_script_resolve, verdict: abi_script_host.c.ke_script_resolve) void {
    if (out != null) out.* = verdict;
}

/// Scans the lists of the given types, so only bound entities are candidates. On a second match it
/// returns true with the first match held in the out-entity, as `descendantOf` does.
fn anywhere(s: *State, types: []const abi_script_host.c.ke_script_type_id, wanted: []const u8, found: *abi_asset_resolver.c.ke_entity) bool {
    for (types) |type_id| {
        if (type_id == abi_script_host.c.KE_SCRIPT_TYPE_NONE or type_id > s.type_count) continue;
        for (s.types[type_id - 1].entities.items) |e| {
            if (!matches(s, e, types, wanted)) continue;
            if (found.* != abi_ecs.c.KE_ENTITY_INVALID) return true;
            found.* = e;
        }
    }
    return false;
}

/// Slot `resolve`. Answers a script's borrow from an owner. An ancestor borrow follows parent
/// links upward and takes the first match, so it is never ambiguous; descendant and anywhere
/// borrows search the owner's subtree depth-first or the type's own list, and a second match is
/// reported as ambiguous rather than picked from. A node matches when its binding has one of the
/// wanted types and, if a name was given, its name equals it. Returns the entity found, or
/// `KE_ENTITY_INVALID` when nothing matched or when more than one node did. The verdict is
/// written to the out-parameter when the caller passes one.
fn resolve(
    self_in: ?*abi_script_host.c.ke_script_host,
    owner: abi_asset_resolver.c.ke_entity,
    types_in: [*c]const abi_script_host.c.ke_script_type_id,
    type_count: u32,
    name_in: [*c]const u8,
    reach: abi_script_host.c.ke_script_borrow,
    out_why: [*c]abi_script_host.c.ke_script_resolve,
) callconv(.c) abi_asset_resolver.c.ke_entity {
    const self = self_in orelse {
        why(out_why, abi_script_host.c.KE_SCRIPT_RESOLVE_NONE);
        return abi_ecs.c.KE_ENTITY_INVALID;
    };
    const s = stateOf(self);
    const wanted = if (name_in == null) &[_]u8{} else std.mem.span(name_in);
    const types: []const abi_script_host.c.ke_script_type_id = if (types_in == null) &.{} else types_in[0..type_count];

    if (reach == abi_script_host.c.KE_SCRIPT_BORROW_ANCESTOR) {
        var cur = if (getHierarchy(s, owner)) |h| h.parent else abi_ecs.c.KE_ENTITY_INVALID;
        while (cur != abi_ecs.c.KE_ENTITY_INVALID) {
            if (matches(s, cur, types, wanted)) {
                why(out_why, abi_script_host.c.KE_SCRIPT_RESOLVE_FOUND);
                return cur;
            }
            cur = if (getHierarchy(s, cur)) |h| h.parent else abi_ecs.c.KE_ENTITY_INVALID;
        }
        why(out_why, abi_script_host.c.KE_SCRIPT_RESOLVE_NONE);
        return abi_ecs.c.KE_ENTITY_INVALID;
    }

    var found: abi_asset_resolver.c.ke_entity = abi_ecs.c.KE_ENTITY_INVALID;
    const ambiguous = switch (reach) {
        abi_script_host.c.KE_SCRIPT_BORROW_ANYWHERE => anywhere(s, types, wanted, &found),
        else => descendantOf(s, owner, types, wanted, &found),
    };
    if (ambiguous) {
        why(out_why, abi_script_host.c.KE_SCRIPT_RESOLVE_AMBIGUOUS);
        return abi_ecs.c.KE_ENTITY_INVALID;
    }
    why(out_why, if (found == abi_ecs.c.KE_ENTITY_INVALID) abi_script_host.c.KE_SCRIPT_RESOLVE_NONE else abi_script_host.c.KE_SCRIPT_RESOLVE_FOUND);
    return found;
}

/// The destroy of the handle. The binding components stay registered in the ecs and no bound
/// instance is released. The host frees only its own lists, table and state.
fn destroy(self_in: ?*abi_script_host.c.ke_script_host) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    for (s.types[0..s.type_count]) |*t| {
        t.entities.deinit(heap.gpa);
        heap.gpa.free(t.name);
        heap.gpa.free(t.components);
    }
    for (s.aliases.items) |a| heap.gpa.free(a.alias);
    s.aliases.deinit(heap.gpa);
    heap.gpa.free(s.types);
    heap.gpa.destroy(s);
}

/// Factory. Needs the hierarchy and name components to exist already, so a scene tree is created
/// first; registers the binding component "script_instance" on the ecs and sizes the type table
/// from the params, a zero field or a null pointer selecting the default. Fails as an invalid
/// argument for a null ecs or out-parameter or an ecs without component lookup and get; as not
/// found when the hierarchy and name components are not registered yet; as out of memory when the
/// state or the type table cannot be allocated; and with the ecs's code when it refuses the
/// binding or group component. Each failure releases what the call had allocated and leaves the
/// handle zeroed.
pub export fn ke_script_host_create(
    ecs_in: ?*abi_ecs.c.ke_ecs,
    params: [*c]const abi_framework_factory.c.ke_script_host_params,
    out_host: ?*abi_script_host.c.ke_script_host_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_host orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_script_host.c.ke_script_host_handle);
    const ecs = ecs_in orelse return R.code(error.InvalidArgument);
    if (ecs.component_lookup == null or ecs.component_get == null) return R.code(error.InvalidArgument);
    const n_types = if (params != null) orDefault(params.*.max_types, default_max_types) else default_max_types;
    out.* = create(ecs, n_types) catch |err| return R.code(err);
    return R.ok;
}

fn create(ecs: *abi_ecs.c.ke_ecs, n_types: u32) R.Error!abi_script_host.c.ke_script_host_handle {
    var hierarchy_meta: abi_ecs.c.ke_component_meta = undefined;
    var name_meta: abi_ecs.c.ke_component_meta = undefined;
    if (!ecs.component_lookup.?(ecs, abi_framework_components.c.KE_COMPONENT_NAME_HIERARCHY, &hierarchy_meta) or
        !ecs.component_lookup.?(ecs, abi_framework_components.c.KE_COMPONENT_NAME_NAME, &name_meta))
    {
        log.warn("script host: hierarchy and name components are not registered; create a scene tree first", .{});
        return error.NotFound;
    }

    const s = try heap.gpa.create(State);
    errdefer heap.gpa.destroy(s);
    s.types = try heap.gpa.alloc(ScriptType, n_types);
    errdefer heap.gpa.free(s.types);
    s.aliases = .empty;

    s.ecs = ecs;
    s.hierarchy_cid = hierarchy_meta.cid;
    s.name_cid = name_meta.cid;
    s.binding_cid = 0;
    s.tag_group_cid = 0;
    try R.check(ecs.component_register.?(ecs, &abi_ecs.c.ke_component_params{ .name = binding_component, .size = @sizeOf(Binding), .alignment = @alignOf(Binding), .fields = null, .field_count = 0 }, &s.binding_cid));
    try R.check(ecs.component_register.?(ecs, &abi_ecs.c.ke_component_params{ .name = tag_group_component, .size = 0, .alignment = 0, .fields = null, .field_count = 0 }, &s.tag_group_cid));
    s.type_count = 0;

    s.api = .{
        .handle = s,
        .register_type = &registerType,
        .type_lookup = &typeLookup,
        .register_type_alias = &registerTypeAlias,
        .type_resolve = &typeResolve,
        .type_components = &typeComponents,
        .type_reach = &typeReach,
        .type_tag = &typeTag,
        .type_tag_group = &typeTagGroup,
        .bind = &bind,
        .unbind = &unbind,
        .bind_deferred = &bindDeferred,
        .unbind_deferred = &unbindDeferred,
        .instance_of = &instanceOf,
        .instance_count = &instanceCount,
        .instances = &instances,
        .resolve = &resolve,
    };

    return .{ .ref = &s.api, .destroy = &destroy };
}

const testing = std.testing;
const scene_tree = @import("scene_tree.zig");

const Harness = struct {
    tree: scene_tree.Fixture,
    handle: abi_script_host.c.ke_script_host_handle,

    fn init(self: *Harness) !void {
        try self.tree.init();
        try testing.expectEqual(R.ok, ke_script_host_create(&self.tree.ecs.vtable, null, &self.handle));
    }

    fn deinit(self: *Harness) void {
        if (self.handle.destroy) |d| d(self.handle.ref);
        self.tree.deinit();
    }

    fn host(self: *Harness) *abi_script_host.c.ke_script_host {
        return self.handle.ref.?;
    }

    fn declare(self: *Harness, name: [*c]const u8, reach: abi_script_host.c.ke_script_reach) !abi_script_host.c.ke_script_type_id {
        var id: abi_script_host.c.ke_script_type_id = abi_script_host.c.KE_SCRIPT_TYPE_NONE;
        const components = [_]abi_asset_resolver.c.ke_component_id{ 1, 2 };
        try testing.expectEqual(R.ok, self.host().register_type.?(self.host(), name, &components, components.len, reach, &id));
        return id;
    }
};

test "a type registered twice under one name is the same type" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const first = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const again = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);

    try testing.expectEqual(first, again);
}

test "a type re-registered with a different reach is refused" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    _ = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);

    var id: abi_script_host.c.ke_script_type_id = abi_script_host.c.KE_SCRIPT_TYPE_NONE;
    const components = [_]abi_asset_resolver.c.ke_component_id{ 1, 2 };
    try testing.expectEqual(R.code(error.AlreadyExists), h.host().register_type.?(h.host(), "pong.paddle", &components, components.len, abi_script_host.c.KE_SCRIPT_REACH_ANY, &id));
}

test "an unregistered type name resolves to nothing" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    var id: abi_script_host.c.ke_script_type_id = 12345;
    try testing.expect(!h.host().type_lookup.?(h.host(), "pong.nobody", &id));
}

test "an unknown type reaches anywhere, because refusing to parallelise it is the safe answer" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    try testing.expectEqual(@as(abi_script_host.c.ke_script_reach, abi_script_host.c.KE_SCRIPT_REACH_ANY), h.host().type_reach.?(h.host(), 9999));
    try testing.expectEqual(@as(abi_script_host.c.ke_script_reach, abi_script_host.c.KE_SCRIPT_REACH_ANY), h.host().type_reach.?(h.host(), abi_script_host.c.KE_SCRIPT_TYPE_NONE));
}

test "a type reports the components it was registered with" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);

    var count: u32 = 0;
    const comps = h.host().type_components.?(h.host(), id, &count);
    try testing.expectEqual(@as(u32, 2), count);
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_component_id, 1), comps.?[0]);
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_component_id, 2), comps.?[1]);
}

test "an entity carries the instance it was bound to" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const e = h.tree.create("Left", 0);
    var marker: u32 = 7;

    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), e, id, &marker));

    var out_type: abi_script_host.c.ke_script_type_id = abi_script_host.c.KE_SCRIPT_TYPE_NONE;
    var out_instance: ?*anyopaque = null;
    try testing.expect(h.host().instance_of.?(h.host(), e, &out_type, &out_instance));
    try testing.expectEqual(id, out_type);
    try testing.expectEqual(@as(?*anyopaque, &marker), out_instance);
}

test "each type has its own tag, apart from the group of tags, carried by a bound instance until it is unbound" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const paddle = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = try h.declare("pong.ball", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const tag = h.host().type_tag.?(h.host(), paddle);
    try testing.expect(tag != 0);
    try testing.expect(tag != h.host().type_tag.?(h.host(), ball));
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_component_id, 0), h.host().type_tag.?(h.host(), 9999));
    const group = h.host().type_tag_group.?(h.host());
    try testing.expect(group != 0 and group != tag);

    const e = h.tree.create("Left", 0);
    var marker: u32 = 7;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), e, paddle, &marker));
    const ecs = &h.tree.ecs.vtable;
    try testing.expect(ecs.component_get.?(ecs, e, tag) != null);

    try R.check(h.host().unbind.?(h.host(), e));
    try testing.expect(ecs.component_get.?(ecs, e, tag) == null);
}

test "binding over an existing instance is refused rather than dropping it silently" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const e = h.tree.create("Left", 0);
    var first: u32 = 1;
    var second: u32 = 2;

    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), e, id, &first));
    try testing.expectEqual(R.code(error.AlreadyExists), h.host().bind.?(h.host(), e, id, &second));

    var out_instance: ?*anyopaque = null;
    _ = h.host().instance_of.?(h.host(), e, null, &out_instance);
    try testing.expectEqual(@as(?*anyopaque, &first), out_instance);
}

test "an entity nobody bound has no instance" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const e = h.tree.create("Scenery", 0);
    try testing.expect(!h.host().instance_of.?(h.host(), e, null, null));
}

test "instance count follows bind and unbind" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const a = h.tree.create("Left", 0);
    const b = h.tree.create("Right", 0);
    var ma: u32 = 1;
    var mb: u32 = 2;

    try testing.expectEqual(@as(u32, 0), h.host().instance_count.?(h.host(), id));
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), a, id, &ma));
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), b, id, &mb));
    try testing.expectEqual(@as(u32, 2), h.host().instance_count.?(h.host(), id));

    try R.check(h.host().unbind.?(h.host(), a));
    try testing.expectEqual(@as(u32, 1), h.host().instance_count.?(h.host(), id));
    try testing.expect(!h.host().instance_of.?(h.host(), a, null, null));
}

test "unbinding an entity keeps the others in binding order" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    var marks = [_]u32{ 1, 2, 3, 4 };
    var entities: [4]abi_asset_resolver.c.ke_entity = undefined;
    for (&entities, &marks, 0..) |*e, *m, i| {
        e.* = h.tree.create(if (i == 0) "A" else if (i == 1) "B" else if (i == 2) "C" else "D", 0);
        try testing.expectEqual(R.ok, h.host().bind.?(h.host(), e.*, id, m));
    }

    try R.check(h.host().unbind.?(h.host(), entities[1]));
    var count: u32 = 0;
    const listed = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqualSlices(abi_asset_resolver.c.ke_entity, &.{ entities[0], entities[2], entities[3] }, listed.?[0..count]);

    try R.check(h.host().unbind.?(h.host(), entities[2]));
    const after = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqualSlices(abi_asset_resolver.c.ke_entity, &.{ entities[0], entities[3] }, after.?[0..count]);
}

test "a deferred bind and unbind take effect only once the recorded commands are applied" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const a = h.tree.create("Left", 0);
    var ma: u32 = 1;
    var rec = scene_tree.RecordingCommands.init(&h.tree.ecs.vtable);

    try testing.expectEqual(R.ok, h.host().bind_deferred.?(h.host(), a, id, &ma, rec.bind()));
    try testing.expectEqual(@as(u32, 0), h.host().instance_count.?(h.host(), id));
    try testing.expect(!h.host().instance_of.?(h.host(), a, null, null));

    rec.apply();
    try testing.expectEqual(@as(u32, 1), h.host().instance_count.?(h.host(), id));
    var seen: ?*anyopaque = null;
    try testing.expect(h.host().instance_of.?(h.host(), a, null, &seen));
    try testing.expectEqual(@as(?*anyopaque, &ma), seen);

    try testing.expectEqual(R.ok, h.host().unbind_deferred.?(h.host(), a, rec.bind()));
    try testing.expectEqual(@as(u32, 1), h.host().instance_count.?(h.host(), id));
    rec.apply();
    try testing.expectEqual(@as(u32, 0), h.host().instance_count.?(h.host(), id));
}

test "a deferred bind without a command queue, a type, or an entity is refused" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const a = h.tree.create("Left", 0);
    var m: u32 = 1;
    var rec = scene_tree.RecordingCommands.init(&h.tree.ecs.vtable);

    try testing.expectEqual(R.code(error.InvalidArgument), h.host().bind_deferred.?(h.host(), a, id, &m, null));
    try testing.expectEqual(R.code(error.NotFound), h.host().bind_deferred.?(h.host(), a, 9999, &m, rec.bind()));
    try testing.expectEqual(R.code(error.InvalidArgument), h.host().bind_deferred.?(h.host(), abi_ecs.c.KE_ENTITY_INVALID, id, &m, rec.bind()));
    try testing.expectEqual(R.code(error.InvalidArgument), h.host().unbind_deferred.?(h.host(), a, null));
}

test "a type lists the entities bound to it" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const a = h.tree.create("Left", 0);
    const b = h.tree.create("Right", 0);
    var ma: u32 = 1;
    var mb: u32 = 2;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), a, id, &ma));
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), b, id, &mb));

    var count: u32 = 0;
    const listed = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqual(@as(u32, 2), count);
    try testing.expectEqual(a, listed.?[0]);
    try testing.expectEqual(b, listed.?[1]);
}

test "unbinding one instance leaves every other one reachable" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    var entities: [4]abi_asset_resolver.c.ke_entity = undefined;
    var marks = [_]u32{ 1, 2, 3, 4 };
    for (&entities, 0..) |*e, i| {
        e.* = h.tree.create("Node", 0);
        try testing.expectEqual(R.ok, h.host().bind.?(h.host(), e.*, id, &marks[i]));
    }

    try R.check(h.host().unbind.?(h.host(), entities[0]));
    try R.check(h.host().unbind.?(h.host(), entities[2]));

    var count: u32 = 0;
    const listed = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqual(@as(u32, 2), count);

    for (listed.?[0..count]) |e| {
        try testing.expect(e != entities[0] and e != entities[2]);
        try testing.expect(h.host().instance_of.?(h.host(), e, null, null));
    }
}

test "the last instance unbound empties its type" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const only = h.tree.create("Only", 0);
    var mark: u32 = 1;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), only, id, &mark));
    try R.check(h.host().unbind.?(h.host(), only));

    var count: u32 = 1;
    _ = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqual(@as(u32, 0), count);
    try testing.expectEqual(@as(u32, 0), h.host().instance_count.?(h.host(), id));
}

test "a descendant of the wanted type is found through intermediate nodes" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const holder = h.tree.create("Sounds", ball);
    const hit = h.tree.create("HitSound", holder);
    var marker: u32 = 1;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), hit, audio, &marker));

    try testing.expectEqual(hit, h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_DESCENDANT, null));
}

test "a descendant named by the borrow is picked out of several of its type" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const hit = h.tree.create("HitSound", ball);
    const score = h.tree.create("ScoreSound", ball);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), hit, audio, &m1));
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), score, audio, &m2));

    try testing.expectEqual(score, h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "ScoreSound", abi_script_host.c.KE_SCRIPT_BORROW_DESCENDANT, null));
}

test "an unnamed borrow answered by two nodes resolves to nothing instead of guessing" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const hit = h.tree.create("HitSound", ball);
    const score = h.tree.create("ScoreSound", ball);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), hit, audio, &m1));
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), score, audio, &m2));

    try testing.expectEqual(@as(abi_asset_resolver.c.ke_entity, abi_ecs.c.KE_ENTITY_INVALID), h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_DESCENDANT, null));
}

test "an invalid answer says whether nothing matched or too much did" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    var verdict: abi_script_host.c.ke_script_resolve = abi_script_host.c.KE_SCRIPT_RESOLVE_FOUND;

    _ = h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_DESCENDANT, &verdict);
    try testing.expectEqual(@as(abi_script_host.c.ke_script_resolve, abi_script_host.c.KE_SCRIPT_RESOLVE_NONE), verdict);

    const hit = h.tree.create("HitSound", ball);
    var m1: u32 = 1;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), hit, audio, &m1));
    try testing.expectEqual(hit, h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_DESCENDANT, &verdict));
    try testing.expectEqual(@as(abi_script_host.c.ke_script_resolve, abi_script_host.c.KE_SCRIPT_RESOLVE_FOUND), verdict);

    const score = h.tree.create("ScoreSound", ball);
    var m2: u32 = 2;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), score, audio, &m2));
    _ = h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_DESCENDANT, &verdict);
    try testing.expectEqual(@as(abi_script_host.c.ke_script_resolve, abi_script_host.c.KE_SCRIPT_RESOLVE_AMBIGUOUS), verdict);
}

test "an ancestor that is not there reads as none, never as ambiguous" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const field = try h.declare("pong.field", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const lonely = h.tree.create("Lonely", 0);
    var verdict: abi_script_host.c.ke_script_resolve = abi_script_host.c.KE_SCRIPT_RESOLVE_AMBIGUOUS;

    _ = h.host().resolve.?(h.host(), lonely, &[_]abi_script_host.c.ke_script_type_id{field}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_ANCESTOR, &verdict);
    try testing.expectEqual(@as(abi_script_host.c.ke_script_resolve, abi_script_host.c.KE_SCRIPT_RESOLVE_NONE), verdict);
}

test "a node of the wanted type outside the subtree is not a descendant" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const elsewhere = h.tree.create("Music", 0);
    var marker: u32 = 1;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), elsewhere, audio, &marker));

    try testing.expectEqual(@as(abi_asset_resolver.c.ke_entity, abi_ecs.c.KE_ENTITY_INVALID), h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_DESCENDANT, null));
}

test "a borrow reaching anywhere finds a node the subtree does not contain" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const elsewhere = h.tree.create("Music", 0);
    var marker: u32 = 1;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), elsewhere, audio, &marker));

    try testing.expectEqual(elsewhere, h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_ANYWHERE, null));
    try testing.expectEqual(elsewhere, h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "Music", abi_script_host.c.KE_SCRIPT_BORROW_ANYWHERE, null));
}

test "two nodes of one type anywhere are ambiguous until the borrow names one" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const music = h.tree.create("Music", 0);
    const hit = h.tree.create("HitSound", 0);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), music, audio, &m1));
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), hit, audio, &m2));

    var verdict: abi_script_host.c.ke_script_resolve = abi_script_host.c.KE_SCRIPT_RESOLVE_FOUND;
    _ = h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_ANYWHERE, &verdict);
    try testing.expectEqual(@as(abi_script_host.c.ke_script_resolve, abi_script_host.c.KE_SCRIPT_RESOLVE_AMBIGUOUS), verdict);

    try testing.expectEqual(hit, h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{audio}, 1, "HitSound", abi_script_host.c.KE_SCRIPT_BORROW_ANYWHERE, &verdict));
    try testing.expectEqual(@as(abi_script_host.c.ke_script_resolve, abi_script_host.c.KE_SCRIPT_RESOLVE_FOUND), verdict);
}

test "a borrow reaching anywhere does not see a type nobody registered" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const ball = h.tree.create("Ball", 0);
    var verdict: abi_script_host.c.ke_script_resolve = abi_script_host.c.KE_SCRIPT_RESOLVE_FOUND;
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_entity, abi_ecs.c.KE_ENTITY_INVALID),
        h.host().resolve.?(h.host(), ball, &[_]abi_script_host.c.ke_script_type_id{abi_script_host.c.KE_SCRIPT_TYPE_NONE}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_ANYWHERE, &verdict));
    try testing.expectEqual(@as(abi_script_host.c.ke_script_resolve, abi_script_host.c.KE_SCRIPT_RESOLVE_NONE), verdict);
}

test "the nearest ancestor of the wanted type wins over a further one" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const field = try h.declare("pong.field", abi_script_host.c.KE_SCRIPT_REACH_ANY);
    const outer = h.tree.create("Outer", 0);
    const inner = h.tree.create("Inner", outer);
    const leaf = h.tree.create("Leaf", inner);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), outer, field, &m1));
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), inner, field, &m2));

    try testing.expectEqual(inner, h.host().resolve.?(h.host(), leaf, &[_]abi_script_host.c.ke_script_type_id{field}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_ANCESTOR, null));
}

test "a node is not its own ancestor" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const field = try h.declare("pong.field", abi_script_host.c.KE_SCRIPT_REACH_ANY);
    const node = h.tree.create("Field", 0);
    var marker: u32 = 1;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), node, field, &marker));

    try testing.expectEqual(@as(abi_asset_resolver.c.ke_entity, abi_ecs.c.KE_ENTITY_INVALID), h.host().resolve.?(h.host(), node, &[_]abi_script_host.c.ke_script_type_id{field}, 1, "", abi_script_host.c.KE_SCRIPT_BORROW_ANCESTOR, null));
}

test "the nearest ancestor bound to any of the wanted types wins" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const field = try h.declare("pong.field", abi_script_host.c.KE_SCRIPT_REACH_ANY);
    const arena = try h.declare("pong.arena", abi_script_host.c.KE_SCRIPT_REACH_ANY);
    const outer = h.tree.create("Outer", 0);
    const inner = h.tree.create("Inner", outer);
    const leaf = h.tree.create("Leaf", inner);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), outer, field, &m1));
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), inner, arena, &m2));

    try testing.expectEqual(inner, h.host().resolve.?(h.host(), leaf, &[_]abi_script_host.c.ke_script_type_id{ field, arena }, 2, "", abi_script_host.c.KE_SCRIPT_BORROW_ANCESTOR, null));
}

test "two descendants bound to two of the wanted types are ambiguous" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const hit = try h.declare("pong.hit", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const score = try h.declare("pong.score", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const a = h.tree.create("A", ball);
    const b = h.tree.create("B", ball);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), a, hit, &m1));
    try testing.expectEqual(R.ok, h.host().bind.?(h.host(), b, score, &m2));

    var verdict: abi_script_host.c.ke_script_resolve = undefined;
    const types = [_]abi_script_host.c.ke_script_type_id{ hit, score };
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_entity, abi_ecs.c.KE_ENTITY_INVALID), h.host().resolve.?(h.host(), ball, &types, 2, "", abi_script_host.c.KE_SCRIPT_BORROW_DESCENDANT, &verdict));
    try testing.expectEqual(abi_script_host.c.KE_SCRIPT_RESOLVE_AMBIGUOUS, verdict);
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_entity, abi_ecs.c.KE_ENTITY_INVALID), h.host().resolve.?(h.host(), ball, &types, 2, "", abi_script_host.c.KE_SCRIPT_BORROW_ANYWHERE, &verdict));
    try testing.expectEqual(abi_script_host.c.KE_SCRIPT_RESOLVE_AMBIGUOUS, verdict);
    try testing.expectEqual(b, h.host().resolve.?(h.host(), ball, &types, 2, "B", abi_script_host.c.KE_SCRIPT_BORROW_DESCENDANT, null));
}

test "a type resolves by its name and by an alias only one type answers to" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const paddle = try h.declare("pong.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const tennis = try h.declare("tennis.paddle", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const ball = try h.declare("pong.ball", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    const host = h.host();
    try R.check(host.register_type_alias.?(host, "ball", ball));
    try R.check(host.register_type_alias.?(host, "ball", ball));
    try R.check(host.register_type_alias.?(host, "paddle", paddle));
    try R.check(host.register_type_alias.?(host, "paddle", tennis));

    var id: abi_script_host.c.ke_script_type_id = 0;
    try R.check(host.type_resolve.?(host, "ball", &id));
    try testing.expectEqual(ball, id);
    try R.check(host.type_resolve.?(host, "tennis.paddle", &id));
    try testing.expectEqual(tennis, id);
    try testing.expectError(error.InvalidArgument, R.check(host.type_resolve.?(host, "paddle", &id)));
    try testing.expectError(error.NotFound, R.check(host.type_resolve.?(host, "wall", &id)));
    try testing.expectError(error.InvalidArgument, R.check(host.register_type_alias.?(host, "x", 99)));
}

test "creating and destroying a script host leaves no block allocated" {
    var h: Harness = undefined;
    try h.init();
    _ = try h.declare("LeakProbe", abi_script_host.c.KE_SCRIPT_REACH_SELF);
    h.deinit();
    try heap.expectNoLeaks();
}

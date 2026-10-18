//! The script host: the record of which entity a script instance is bound to, and the lookups a
//! script makes from an entity into the scene around it.

const std = @import("std");

const c = @import("c");
const heap = @import("heap");

const E = @import("kerror").Errors(c);

const default_max_types = 64;

/// One record per registered name, kept in `State.types` for the life of the host. `entities` lists
/// the bound entities of this type, and a binding's `slot` is an index into that list. `tag` is the
/// component every bound entity of the type carries beside its binding, so a query can match the
/// instances of one type.
const ScriptType = struct {
    name: []u8,
    components: []c.ke_component_id,
    reach: c.ke_script_reach,
    tag: c.ke_component_id,

    entities: std.ArrayList(c.ke_entity),
};

/// The component stored in the ecs for each bound entity. `slot` is the index of the entity in its
/// type's `entities` list and is rewritten whenever a swap-removal moves that entity. `type_id` is
/// `KE_SCRIPT_TYPE_NONE` while an unbind is removing the component. `instance` is opaque: it is
/// copied in and out and never dereferenced.
const Binding = extern struct {
    type_id: c.ke_script_type_id,
    instance: ?*anyopaque,

    slot: u32,
};

const binding_component = "script_instance";
const tag_prefix = "script_type:";

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
    api: c.ke_script_host,
    ecs: *c.ke_ecs,
    hierarchy_cid: c.ke_component_id,
    name_cid: c.ke_component_id,

    binding_cid: c.ke_component_id,

    types: []ScriptType,
    type_count: u32,
};

fn stateOf(self: *c.ke_script_host) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn orDefault(v: u32, d: u32) u32 {
    return if (v == 0) d else v;
}

fn typeAt(s: *State, id: c.ke_script_type_id) ?*ScriptType {
    if (id == c.KE_SCRIPT_TYPE_NONE or id > s.type_count) return null;
    return &s.types[id - 1];
}

fn bindingOf(s: *State, entity: c.ke_entity) ?*Binding {
    const raw = s.ecs.component_get.?(s.ecs, entity, s.binding_cid) orelse return null;
    const b: *Binding = @ptrCast(@alignCast(raw));
    return if (b.type_id == c.KE_SCRIPT_TYPE_NONE) null else b;
}

fn getHierarchy(s: *State, e: c.ke_entity) ?*c.ke_hierarchy_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.hierarchy_cid)));
}

fn getName(s: *State, e: c.ke_entity) []const u8 {
    const raw = s.ecs.component_get.?(s.ecs, e, s.name_cid) orelse return &[_]u8{};
    const comp: *const c.ke_name_component = @ptrCast(@alignCast(raw));
    return std.mem.sliceTo(&comp.name, 0);
}

fn matches(s: *State, entity: c.ke_entity, type_id: c.ke_script_type_id, wanted: []const u8) bool {
    const b = bindingOf(s, entity) orelse return false;
    if (b.type_id != type_id) return false;
    if (wanted.len == 0) return true;
    return std.mem.eql(u8, getName(s, entity), wanted);
}

/// Slot `register_type`. Registering a name again with the same reach and components returns the
/// id the first registration got. The same name with any other description fails with
/// already-exists and leaves the table unchanged. A new name fails with out-of-memory when the
/// table is full. A null host, name or `out_id`, an empty name, or a component count without
/// components fails as an invalid argument. Each
/// failure returns false.
fn registerType(
    self_in: ?*c.ke_script_host,
    name_in: [*c]const u8,
    components_in: [*c]const c.ke_component_id,
    component_count: u32,
    reach: c.ke_script_reach,
    out_id: [*c]c.ke_script_type_id,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "script host is null", @src());
        return false;
    };
    if (name_in == null or out_id == null) {
        E.fail(out_error, .invalid_argument, "type name and out_id are required", @src());
        return false;
    }
    const s = stateOf(self);
    const name = std.mem.span(name_in);
    if (name.len == 0) {
        E.fail(out_error, .invalid_argument, "script type name is empty", @src());
        return false;
    }
    if (component_count > 0 and components_in == null) {
        E.fail(out_error, .invalid_argument, "component count is non-zero but no components were given", @src());
        return false;
    }

    for (s.types[0..s.type_count], 0..) |*t, i| {
        if (!std.mem.eql(u8, t.name, name)) continue;
        if (t.components.len != component_count or t.reach != reach) {
            E.fail(out_error, .already_exists, "script type already registered with a different description", @src());
            return false;
        }
        for (0..component_count) |k| {
            if (t.components[k] == components_in[k]) continue;
            E.fail(out_error, .already_exists, "script type already registered with different components", @src());
            return false;
        }
        out_id.* = @intCast(i + 1);
        return true;
    }

    if (s.type_count == s.types.len) {
        E.fail(out_error, .out_of_memory, "script type table is full", @src());
        return false;
    }

    const owned_name = heap.gpa.dupe(u8, name) catch {
        E.fail(out_error, .out_of_memory, "script type name allocation failed", @src());
        return false;
    };
    const owned_components = heap.gpa.dupe(c.ke_component_id, if (component_count > 0) components_in[0..component_count] else &.{}) catch {
        heap.gpa.free(owned_name);
        E.fail(out_error, .out_of_memory, "script type component list allocation failed", @src());
        return false;
    };
    const tag_name = std.fmt.allocPrintSentinel(heap.gpa, "{s}{s}", .{ tag_prefix, name }, 0) catch {
        heap.gpa.free(owned_name);
        heap.gpa.free(owned_components);
        E.fail(out_error, .out_of_memory, "script type tag name allocation failed", @src());
        return false;
    };
    defer heap.gpa.free(tag_name);
    const tag = s.ecs.component_register.?(s.ecs, tag_name.ptr, 0, null, 0, out_error);
    if (tag == 0) {
        heap.gpa.free(owned_name);
        heap.gpa.free(owned_components);
        return false;
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
    return true;
}

/// Slot `type_lookup`. Writes the id registered under the name and returns true; an unknown name
/// returns false without an error.
fn typeLookup(
    self_in: ?*c.ke_script_host,
    name_in: [*c]const u8,
    out_id: [*c]c.ke_script_type_id,
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

/// Slot `type_components`. The returned pointer aims into the record itself, so it stays valid
/// until `destroy`. An id that is not registered returns null with the count written as zero.
fn typeComponents(
    self_in: ?*c.ke_script_host,
    type_id: c.ke_script_type_id,
    out_count: [*c]u32,
) callconv(.c) [*c]const c.ke_component_id {
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
fn typeReach(self_in: ?*c.ke_script_host, type_id: c.ke_script_type_id) callconv(.c) c.ke_script_reach {
    const self = self_in orelse return c.KE_SCRIPT_REACH_ANY;
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse return c.KE_SCRIPT_REACH_ANY;
    return t.reach;
}

/// Slot `type_tag`. Answers the tag `registerType` registered for the type, or 0 for an id that is
/// not registered.
fn typeTag(self_in: ?*c.ke_script_host, type_id: c.ke_script_type_id) callconv(.c) c.ke_component_id {
    const self = self_in orelse return 0;
    const t = typeAt(stateOf(self), type_id) orelse return 0;
    return t.tag;
}

/// Slot `bind`. Attaches the instance to the entity at once, so it belongs to code that no system
/// body runs beside. Fails as invalid argument for a null host or the invalid entity, as not
/// found for an unregistered type id, as already exists for an entity that carries an instance,
/// and as out of memory when the component or the type's list cannot grow; each returns false.
fn bind(
    self_in: ?*c.ke_script_host,
    entity: c.ke_entity,
    type_id: c.ke_script_type_id,
    instance: ?*anyopaque,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "script host is null", @src());
        return false;
    };
    return bindNow(stateOf(self), entity, type_id, instance, out_error);
}

/// The one place a binding is attached: `bind` calls it directly, and `cbBind` calls it when a
/// recorded bind is applied. On failure the entity is left without a binding component, so no
/// caller sees a half-made binding.
fn bindNow(
    s: *State,
    entity: c.ke_entity,
    type_id: c.ke_script_type_id,
    instance: ?*anyopaque,
    out_error: [*c][*c]c.ke_error,
) bool {
    const t = typeAt(s, type_id) orelse {
        E.fail(out_error, .not_found, "script type id was never registered", @src());
        return false;
    };
    if (entity == c.KE_ENTITY_INVALID) {
        E.fail(out_error, .invalid_argument, "cannot bind an instance to an invalid entity", @src());
        return false;
    }
    if (bindingOf(s, entity) != null) {
        E.fail(out_error, .already_exists, "entity already carries a script instance", @src());
        return false;
    }

    _ = s.ecs.component_add.?(s.ecs, entity, s.binding_cid) orelse {
        E.fail(out_error, .out_of_memory, "could not attach the script instance component", @src());
        return false;
    };
    t.entities.append(heap.gpa, entity) catch {
        _ = s.ecs.component_remove.?(s.ecs, entity, s.binding_cid);
        E.fail(out_error, .out_of_memory, "could not record the instance in its type", @src());
        return false;
    };

    _ = s.ecs.component_add.?(s.ecs, entity, t.tag);

    const moved = s.ecs.component_get.?(s.ecs, entity, s.binding_cid) orelse {
        _ = t.entities.pop();
        s.ecs.component_remove.?(s.ecs, entity, t.tag);
        _ = s.ecs.component_remove.?(s.ecs, entity, s.binding_cid);
        E.fail(out_error, .out_of_memory, "could not read back the script instance component", @src());
        return false;
    };
    const b: *Binding = @ptrCast(@alignCast(moved));
    b.type_id = type_id;
    b.instance = instance;
    b.slot = @intCast(t.entities.items.len - 1);
    return true;
}

/// A bind waiting in a command queue. `bindDeferred` hands the queue this record's address and
/// size, and `cbBind` reads it when the queue is applied.
const PendingBind = struct {
    s: *State,
    entity: c.ke_entity,
    type_id: c.ke_script_type_id,
    instance: ?*anyopaque,
};

const PendingUnbind = struct {
    s: *State,
    entity: c.ke_entity,
};

/// Run by the command queue when a recorded bind is applied. It passes no error channel, so a bind
/// that fails at that point is dropped and nothing reports it.
fn cbBind(_: ?*c.ke_ecs, user: ?*anyopaque) callconv(.c) void {
    const p: *const PendingBind = @ptrCast(@alignCast(user.?));
    _ = bindNow(p.s, p.entity, p.type_id, p.instance, null);
}

/// Run by the command queue when a recorded unbind is applied; an entity without a binding by then
/// is left alone.
fn cbUnbind(_: ?*c.ke_ecs, user: ?*anyopaque) callconv(.c) void {
    const p: *const PendingUnbind = @ptrCast(@alignCast(user.?));
    unbindNow(p.s, p.entity);
}

/// Slot `bind_deferred`. Checks the type, the entity and the command queue when it is called, but
/// attaches nothing: the bind is recorded to run `cbBind` when the queue is applied, so the host
/// does not change under a system body that is reading `instances`. A null host or queue or the
/// invalid entity fails as an invalid argument, an unregistered type as not found, and a failed
/// recording reports the queue's error; each returns false.
fn bindDeferred(
    self_in: ?*c.ke_script_host,
    entity: c.ke_entity,
    type_id: c.ke_script_type_id,
    instance: ?*anyopaque,
    commands: ?*c.ke_ecs_commands,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "script host is null", @src());
        return false;
    };
    const cmds = commands orelse {
        E.fail(out_error, .invalid_argument, "a deferred bind needs a command queue", @src());
        return false;
    };
    const s = stateOf(self);
    if (typeAt(s, type_id) == null) {
        E.fail(out_error, .not_found, "script type id was never registered", @src());
        return false;
    }
    if (entity == c.KE_ENTITY_INVALID) {
        E.fail(out_error, .invalid_argument, "cannot bind an instance to an invalid entity", @src());
        return false;
    }
    var pending: PendingBind = .{ .s = s, .entity = entity, .type_id = type_id, .instance = instance };
    return cmds.@"defer".?(cmds, cbBind, &pending, @sizeOf(PendingBind), out_error);
}

/// Slot `unbind_deferred`. Only the host and the command queue are checked when it is called, and
/// a null one fails as an invalid argument; a failed recording reports the queue's error. Each
/// returns false. The entity's binding is looked up when the recorded unbind is applied by
/// `cbUnbind`, not now.
fn unbindDeferred(
    self_in: ?*c.ke_script_host,
    entity: c.ke_entity,
    commands: ?*c.ke_ecs_commands,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "script host is null", @src());
        return false;
    };
    const cmds = commands orelse {
        E.fail(out_error, .invalid_argument, "a deferred unbind needs a command queue", @src());
        return false;
    };
    var pending: PendingUnbind = .{ .s = stateOf(self), .entity = entity };
    return cmds.@"defer".?(cmds, cbUnbind, &pending, @sizeOf(PendingUnbind), out_error);
}

/// Slot `unbind`. Removes the entity's binding at once; an entity with none is left alone.
fn unbind(self_in: ?*c.ke_script_host, entity: c.ke_entity) callconv(.c) void {
    const self = self_in orelse return;
    unbindNow(stateOf(self), entity);
}

/// Removes the entity from its type's list keeping the others in binding order, and rewrites the
/// index of every binding that moved down, so each index keeps naming its entity. An entity with
/// no binding is left untouched.
fn unbindNow(s: *State, entity: c.ke_entity) void {
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
    b.type_id = c.KE_SCRIPT_TYPE_NONE;
    b.instance = null;
    if (tag != 0) s.ecs.component_remove.?(s.ecs, entity, tag);
    _ = s.ecs.component_remove.?(s.ecs, entity, s.binding_cid);
}

/// Slot `instance_of`. Writes the type and instance bound to the entity and returns true; an
/// entity without a binding returns false.
fn instanceOf(
    self_in: ?*c.ke_script_host,
    entity: c.ke_entity,
    out_type: [*c]c.ke_script_type_id,
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
fn instanceCount(self_in: ?*c.ke_script_host, type_id: c.ke_script_type_id) callconv(.c) u32 {
    const self = self_in orelse return 0;
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse return 0;
    return @intCast(t.entities.items.len);
}

/// Slot `instances`. The storage is the type's own list, handed out without a copy. The next bind
/// or unbind of that type may move or reallocate it, so the pointer is valid only until then. An
/// unknown id returns null with the count written as zero.
fn instances(
    self_in: ?*c.ke_script_host,
    type_id: c.ke_script_type_id,
    out_count: [*c]u32,
) callconv(.c) [*c]const c.ke_entity {
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
fn descendantOf(s: *State, parent: c.ke_entity, type_id: c.ke_script_type_id, wanted: []const u8, found: *c.ke_entity) bool {
    const h = getHierarchy(s, parent) orelse return false;
    var child = h.first_child;
    while (child != c.KE_ENTITY_INVALID) {
        if (matches(s, child, type_id, wanted)) {
            if (found.* != c.KE_ENTITY_INVALID) return true;
            found.* = child;
        }
        if (descendantOf(s, child, type_id, wanted, found)) return true;
        child = if (getHierarchy(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
    }
    return false;
}

fn why(out: [*c]c.ke_script_resolve, verdict: c.ke_script_resolve) void {
    if (out != null) out.* = verdict;
}

/// Scans the type's own list, so only bound entities are candidates. On a second match it returns
/// true with the first match held in the out-entity, as `descendantOf` does.
fn anywhere(s: *State, type_id: c.ke_script_type_id, wanted: []const u8, found: *c.ke_entity) bool {
    if (type_id == c.KE_SCRIPT_TYPE_NONE or type_id > s.type_count) return false;
    for (s.types[type_id - 1].entities.items) |e| {
        if (!matches(s, e, type_id, wanted)) continue;
        if (found.* != c.KE_ENTITY_INVALID) return true;
        found.* = e;
    }
    return false;
}

/// Slot `resolve`. Answers a script's borrow from an owner. An ancestor borrow follows parent
/// links upward and takes the first match, so it is never ambiguous; descendant and anywhere
/// borrows search the owner's subtree depth-first or the type's own list, and a second match is
/// reported as ambiguous rather than picked from. A node matches when its binding has the wanted
/// type and, if a name was given, its name equals it. Returns the entity found, or
/// `KE_ENTITY_INVALID` when nothing matched or when more than one node did. The verdict is
/// written to the out-parameter when the caller passes one.
fn resolve(
    self_in: ?*c.ke_script_host,
    owner: c.ke_entity,
    type_id: c.ke_script_type_id,
    name_in: [*c]const u8,
    reach: c.ke_script_borrow,
    out_why: [*c]c.ke_script_resolve,
) callconv(.c) c.ke_entity {
    const self = self_in orelse {
        why(out_why, c.KE_SCRIPT_RESOLVE_NONE);
        return c.KE_ENTITY_INVALID;
    };
    const s = stateOf(self);
    const wanted = if (name_in == null) &[_]u8{} else std.mem.span(name_in);

    if (reach == c.KE_SCRIPT_BORROW_ANCESTOR) {
        var cur = if (getHierarchy(s, owner)) |h| h.parent else c.KE_ENTITY_INVALID;
        while (cur != c.KE_ENTITY_INVALID) {
            if (matches(s, cur, type_id, wanted)) {
                why(out_why, c.KE_SCRIPT_RESOLVE_FOUND);
                return cur;
            }
            cur = if (getHierarchy(s, cur)) |h| h.parent else c.KE_ENTITY_INVALID;
        }
        why(out_why, c.KE_SCRIPT_RESOLVE_NONE);
        return c.KE_ENTITY_INVALID;
    }

    var found: c.ke_entity = c.KE_ENTITY_INVALID;
    const ambiguous = switch (reach) {
        c.KE_SCRIPT_BORROW_ANYWHERE => anywhere(s, type_id, wanted, &found),
        else => descendantOf(s, owner, type_id, wanted, &found),
    };
    if (ambiguous) {
        why(out_why, c.KE_SCRIPT_RESOLVE_AMBIGUOUS);
        return c.KE_ENTITY_INVALID;
    }
    why(out_why, if (found == c.KE_ENTITY_INVALID) c.KE_SCRIPT_RESOLVE_NONE else c.KE_SCRIPT_RESOLVE_FOUND);
    return found;
}

/// The destroy of the handle. The binding components stay registered in the ecs and no bound
/// instance is released. The host frees only its own lists, table and state.
fn destroy(self_in: ?*c.ke_script_host) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    for (s.types[0..s.type_count]) |*t| {
        t.entities.deinit(heap.gpa);
        heap.gpa.free(t.name);
        heap.gpa.free(t.components);
    }
    heap.gpa.free(s.types);
    heap.gpa.destroy(s);
}

/// Factory. Needs the hierarchy and name components to exist already, so a scene tree is created
/// first; registers the binding component "script_instance" on the ecs and sizes the type table
/// from the params, a zero field or a null pointer selecting the default. Fails with
/// invalid-argument for a null ecs, an ecs without component lookup and get, or a binding
/// component that cannot be registered; with not-found when the hierarchy and name components
/// are not registered yet; and with out-of-memory when the state or the type table cannot be
/// allocated. Each failure releases what the call had allocated and returns a zeroed handle.
pub export fn ke_script_host_create(
    ecs_in: ?*c.ke_ecs,
    params: [*c]const c.ke_script_host_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_script_host_handle {
    const null_handle = std.mem.zeroes(c.ke_script_host_handle);

    const ecs = ecs_in orelse {
        E.fail(out_error, .invalid_argument, "script host requires an ecs", @src());
        return null_handle;
    };
    if (ecs.component_lookup == null or ecs.component_get == null) {
        E.fail(out_error, .invalid_argument, "ecs does not expose component lookup", @src());
        return null_handle;
    }

    var hierarchy_meta: c.ke_component_meta = undefined;
    var name_meta: c.ke_component_meta = undefined;
    if (!ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_HIERARCHY, &hierarchy_meta, null) or
        !ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_NAME, &name_meta, null))
    {
        E.fail(out_error, .not_found, "hierarchy and name components are not registered; create a scene tree first", @src());
        return null_handle;
    }

    const n_types = if (params != null) orDefault(params.*.max_types, default_max_types) else default_max_types;

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "script host allocation failed", @src());
        return null_handle;
    };

    s.types = heap.gpa.alloc(ScriptType, n_types) catch {
        E.fail(out_error, .out_of_memory, "script type table allocation failed", @src());
        heap.gpa.destroy(s);
        return null_handle;
    };

    s.ecs = ecs;
    s.hierarchy_cid = hierarchy_meta.cid;
    s.name_cid = name_meta.cid;
    s.binding_cid = ecs.component_register.?(ecs, binding_component, @sizeOf(Binding), null, 0, null);
    if (s.binding_cid == 0) {
        E.fail(out_error, .invalid_argument, "could not register the script instance component", @src());
        heap.gpa.free(s.types);
        heap.gpa.destroy(s);
        return null_handle;
    }
    s.type_count = 0;

    s.api = .{
        .handle = s,
        .register_type = &registerType,
        .type_lookup = &typeLookup,
        .type_components = &typeComponents,
        .type_reach = &typeReach,
        .type_tag = &typeTag,
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
    handle: c.ke_script_host_handle,

    fn init(self: *Harness) !void {
        try self.tree.init();
        self.handle = ke_script_host_create(&self.tree.ecs.vtable, null, null);
        try testing.expect(self.handle.ref != null);
    }

    fn deinit(self: *Harness) void {
        if (self.handle.destroy) |d| d(self.handle.ref);
        self.tree.deinit();
    }

    fn host(self: *Harness) *c.ke_script_host {
        return self.handle.ref;
    }

    fn declare(self: *Harness, name: [*c]const u8, reach: c.ke_script_reach) !c.ke_script_type_id {
        var id: c.ke_script_type_id = c.KE_SCRIPT_TYPE_NONE;
        const components = [_]c.ke_component_id{ 1, 2 };
        try testing.expect(self.host().register_type.?(self.host(), name, &components, components.len, reach, &id, null));
        return id;
    }
};

test "a type registered twice under one name is the same type" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const first = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const again = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);

    try testing.expectEqual(first, again);
}

test "a type re-registered with a different reach is refused" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    _ = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);

    var id: c.ke_script_type_id = c.KE_SCRIPT_TYPE_NONE;
    const components = [_]c.ke_component_id{ 1, 2 };
    try testing.expect(!h.host().register_type.?(h.host(), "pong.paddle", &components, components.len, c.KE_SCRIPT_REACH_ANY, &id, null));
}

test "an unregistered type name resolves to nothing" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    var id: c.ke_script_type_id = 12345;
    try testing.expect(!h.host().type_lookup.?(h.host(), "pong.nobody", &id));
}

test "an unknown type reaches anywhere, because refusing to parallelise it is the safe answer" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    try testing.expectEqual(@as(c.ke_script_reach, c.KE_SCRIPT_REACH_ANY), h.host().type_reach.?(h.host(), 9999));
    try testing.expectEqual(@as(c.ke_script_reach, c.KE_SCRIPT_REACH_ANY), h.host().type_reach.?(h.host(), c.KE_SCRIPT_TYPE_NONE));
}

test "a type reports the components it was registered with" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);

    var count: u32 = 0;
    const comps = h.host().type_components.?(h.host(), id, &count);
    try testing.expectEqual(@as(u32, 2), count);
    try testing.expectEqual(@as(c.ke_component_id, 1), comps[0]);
    try testing.expectEqual(@as(c.ke_component_id, 2), comps[1]);
}

test "an entity carries the instance it was bound to" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const e = h.tree.create("Left", 0);
    var marker: u32 = 7;

    try testing.expect(h.host().bind.?(h.host(), e, id, &marker, null));

    var out_type: c.ke_script_type_id = c.KE_SCRIPT_TYPE_NONE;
    var out_instance: ?*anyopaque = null;
    try testing.expect(h.host().instance_of.?(h.host(), e, &out_type, &out_instance));
    try testing.expectEqual(id, out_type);
    try testing.expectEqual(@as(?*anyopaque, &marker), out_instance);
}

test "each type has its own tag, carried by a bound instance until it is unbound" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const paddle = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const ball = try h.declare("pong.ball", c.KE_SCRIPT_REACH_SELF);
    const tag = h.host().type_tag.?(h.host(), paddle);
    try testing.expect(tag != 0);
    try testing.expect(tag != h.host().type_tag.?(h.host(), ball));
    try testing.expectEqual(@as(c.ke_component_id, 0), h.host().type_tag.?(h.host(), 9999));

    const e = h.tree.create("Left", 0);
    var marker: u32 = 7;
    try testing.expect(h.host().bind.?(h.host(), e, paddle, &marker, null));
    const ecs = &h.tree.ecs.vtable;
    try testing.expect(ecs.component_get.?(ecs, e, tag) != null);

    h.host().unbind.?(h.host(), e);
    try testing.expect(ecs.component_get.?(ecs, e, tag) == null);
}

test "binding over an existing instance is refused rather than dropping it silently" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const e = h.tree.create("Left", 0);
    var first: u32 = 1;
    var second: u32 = 2;

    try testing.expect(h.host().bind.?(h.host(), e, id, &first, null));
    try testing.expect(!h.host().bind.?(h.host(), e, id, &second, null));

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

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const a = h.tree.create("Left", 0);
    const b = h.tree.create("Right", 0);
    var ma: u32 = 1;
    var mb: u32 = 2;

    try testing.expectEqual(@as(u32, 0), h.host().instance_count.?(h.host(), id));
    try testing.expect(h.host().bind.?(h.host(), a, id, &ma, null));
    try testing.expect(h.host().bind.?(h.host(), b, id, &mb, null));
    try testing.expectEqual(@as(u32, 2), h.host().instance_count.?(h.host(), id));

    h.host().unbind.?(h.host(), a);
    try testing.expectEqual(@as(u32, 1), h.host().instance_count.?(h.host(), id));
    try testing.expect(!h.host().instance_of.?(h.host(), a, null, null));
}

test "unbinding an entity keeps the others in binding order" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    var marks = [_]u32{ 1, 2, 3, 4 };
    var entities: [4]c.ke_entity = undefined;
    for (&entities, &marks, 0..) |*e, *m, i| {
        e.* = h.tree.create(if (i == 0) "A" else if (i == 1) "B" else if (i == 2) "C" else "D", 0);
        try testing.expect(h.host().bind.?(h.host(), e.*, id, m, null));
    }

    h.host().unbind.?(h.host(), entities[1]);
    var count: u32 = 0;
    const listed = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqualSlices(c.ke_entity, &.{ entities[0], entities[2], entities[3] }, listed[0..count]);

    h.host().unbind.?(h.host(), entities[2]);
    const after = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqualSlices(c.ke_entity, &.{ entities[0], entities[3] }, after[0..count]);
}

test "a deferred bind and unbind take effect only once the recorded commands are applied" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const a = h.tree.create("Left", 0);
    var ma: u32 = 1;
    var rec = scene_tree.RecordingCommands.init(&h.tree.ecs.vtable);

    try testing.expect(h.host().bind_deferred.?(h.host(), a, id, &ma, rec.bind(), null));
    try testing.expectEqual(@as(u32, 0), h.host().instance_count.?(h.host(), id));
    try testing.expect(!h.host().instance_of.?(h.host(), a, null, null));

    rec.apply();
    try testing.expectEqual(@as(u32, 1), h.host().instance_count.?(h.host(), id));
    var seen: ?*anyopaque = null;
    try testing.expect(h.host().instance_of.?(h.host(), a, null, &seen));
    try testing.expectEqual(@as(?*anyopaque, &ma), seen);

    try testing.expect(h.host().unbind_deferred.?(h.host(), a, rec.bind(), null));
    try testing.expectEqual(@as(u32, 1), h.host().instance_count.?(h.host(), id));
    rec.apply();
    try testing.expectEqual(@as(u32, 0), h.host().instance_count.?(h.host(), id));
}

test "a deferred bind without a command queue, a type, or an entity is refused" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const a = h.tree.create("Left", 0);
    var m: u32 = 1;
    var rec = scene_tree.RecordingCommands.init(&h.tree.ecs.vtable);

    try testing.expect(!h.host().bind_deferred.?(h.host(), a, id, &m, null, null));
    try testing.expect(!h.host().bind_deferred.?(h.host(), a, 9999, &m, rec.bind(), null));
    try testing.expect(!h.host().bind_deferred.?(h.host(), c.KE_ENTITY_INVALID, id, &m, rec.bind(), null));
    try testing.expect(!h.host().unbind_deferred.?(h.host(), a, null, null));
}

test "a type lists the entities bound to it" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const a = h.tree.create("Left", 0);
    const b = h.tree.create("Right", 0);
    var ma: u32 = 1;
    var mb: u32 = 2;
    try testing.expect(h.host().bind.?(h.host(), a, id, &ma, null));
    try testing.expect(h.host().bind.?(h.host(), b, id, &mb, null));

    var count: u32 = 0;
    const listed = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqual(@as(u32, 2), count);
    try testing.expectEqual(a, listed[0]);
    try testing.expectEqual(b, listed[1]);
}

test "unbinding one instance leaves every other one reachable" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    var entities: [4]c.ke_entity = undefined;
    var marks = [_]u32{ 1, 2, 3, 4 };
    for (&entities, 0..) |*e, i| {
        e.* = h.tree.create("Node", 0);
        try testing.expect(h.host().bind.?(h.host(), e.*, id, &marks[i], null));
    }

    h.host().unbind.?(h.host(), entities[0]);
    h.host().unbind.?(h.host(), entities[2]);

    var count: u32 = 0;
    const listed = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqual(@as(u32, 2), count);

    for (listed[0..count]) |e| {
        try testing.expect(e != entities[0] and e != entities[2]);
        try testing.expect(h.host().instance_of.?(h.host(), e, null, null));
    }
}

test "the last instance unbound empties its type" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const only = h.tree.create("Only", 0);
    var mark: u32 = 1;
    try testing.expect(h.host().bind.?(h.host(), only, id, &mark, null));
    h.host().unbind.?(h.host(), only);

    var count: u32 = 1;
    _ = h.host().instances.?(h.host(), id, &count);
    try testing.expectEqual(@as(u32, 0), count);
    try testing.expectEqual(@as(u32, 0), h.host().instance_count.?(h.host(), id));
}

test "a descendant of the wanted type is found through intermediate nodes" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const holder = h.tree.create("Sounds", ball);
    const hit = h.tree.create("HitSound", holder);
    var marker: u32 = 1;
    try testing.expect(h.host().bind.?(h.host(), hit, audio, &marker, null));

    try testing.expectEqual(hit, h.host().resolve.?(h.host(), ball, audio, "", c.KE_SCRIPT_BORROW_DESCENDANT, null));
}

test "a descendant named by the borrow is picked out of several of its type" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const hit = h.tree.create("HitSound", ball);
    const score = h.tree.create("ScoreSound", ball);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expect(h.host().bind.?(h.host(), hit, audio, &m1, null));
    try testing.expect(h.host().bind.?(h.host(), score, audio, &m2, null));

    try testing.expectEqual(score, h.host().resolve.?(h.host(), ball, audio, "ScoreSound", c.KE_SCRIPT_BORROW_DESCENDANT, null));
}

test "an unnamed borrow answered by two nodes resolves to nothing instead of guessing" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const hit = h.tree.create("HitSound", ball);
    const score = h.tree.create("ScoreSound", ball);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expect(h.host().bind.?(h.host(), hit, audio, &m1, null));
    try testing.expect(h.host().bind.?(h.host(), score, audio, &m2, null));

    try testing.expectEqual(@as(c.ke_entity, c.KE_ENTITY_INVALID), h.host().resolve.?(h.host(), ball, audio, "", c.KE_SCRIPT_BORROW_DESCENDANT, null));
}

test "an invalid answer says whether nothing matched or too much did" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    var verdict: c.ke_script_resolve = c.KE_SCRIPT_RESOLVE_FOUND;

    _ = h.host().resolve.?(h.host(), ball, audio, "", c.KE_SCRIPT_BORROW_DESCENDANT, &verdict);
    try testing.expectEqual(@as(c.ke_script_resolve, c.KE_SCRIPT_RESOLVE_NONE), verdict);

    const hit = h.tree.create("HitSound", ball);
    var m1: u32 = 1;
    try testing.expect(h.host().bind.?(h.host(), hit, audio, &m1, null));
    try testing.expectEqual(hit, h.host().resolve.?(h.host(), ball, audio, "", c.KE_SCRIPT_BORROW_DESCENDANT, &verdict));
    try testing.expectEqual(@as(c.ke_script_resolve, c.KE_SCRIPT_RESOLVE_FOUND), verdict);

    const score = h.tree.create("ScoreSound", ball);
    var m2: u32 = 2;
    try testing.expect(h.host().bind.?(h.host(), score, audio, &m2, null));
    _ = h.host().resolve.?(h.host(), ball, audio, "", c.KE_SCRIPT_BORROW_DESCENDANT, &verdict);
    try testing.expectEqual(@as(c.ke_script_resolve, c.KE_SCRIPT_RESOLVE_AMBIGUOUS), verdict);
}

test "an ancestor that is not there reads as none, never as ambiguous" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const field = try h.declare("pong.field", c.KE_SCRIPT_REACH_SELF);
    const lonely = h.tree.create("Lonely", 0);
    var verdict: c.ke_script_resolve = c.KE_SCRIPT_RESOLVE_AMBIGUOUS;

    _ = h.host().resolve.?(h.host(), lonely, field, "", c.KE_SCRIPT_BORROW_ANCESTOR, &verdict);
    try testing.expectEqual(@as(c.ke_script_resolve, c.KE_SCRIPT_RESOLVE_NONE), verdict);
}

test "a node of the wanted type outside the subtree is not a descendant" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const elsewhere = h.tree.create("Music", 0);
    var marker: u32 = 1;
    try testing.expect(h.host().bind.?(h.host(), elsewhere, audio, &marker, null));

    try testing.expectEqual(@as(c.ke_entity, c.KE_ENTITY_INVALID), h.host().resolve.?(h.host(), ball, audio, "", c.KE_SCRIPT_BORROW_DESCENDANT, null));
}

test "a borrow reaching anywhere finds a node the subtree does not contain" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const elsewhere = h.tree.create("Music", 0);
    var marker: u32 = 1;
    try testing.expect(h.host().bind.?(h.host(), elsewhere, audio, &marker, null));

    try testing.expectEqual(elsewhere, h.host().resolve.?(h.host(), ball, audio, "", c.KE_SCRIPT_BORROW_ANYWHERE, null));
    try testing.expectEqual(elsewhere, h.host().resolve.?(h.host(), ball, audio, "Music", c.KE_SCRIPT_BORROW_ANYWHERE, null));
}

test "two nodes of one type anywhere are ambiguous until the borrow names one" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const music = h.tree.create("Music", 0);
    const hit = h.tree.create("HitSound", 0);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expect(h.host().bind.?(h.host(), music, audio, &m1, null));
    try testing.expect(h.host().bind.?(h.host(), hit, audio, &m2, null));

    var verdict: c.ke_script_resolve = c.KE_SCRIPT_RESOLVE_FOUND;
    _ = h.host().resolve.?(h.host(), ball, audio, "", c.KE_SCRIPT_BORROW_ANYWHERE, &verdict);
    try testing.expectEqual(@as(c.ke_script_resolve, c.KE_SCRIPT_RESOLVE_AMBIGUOUS), verdict);

    try testing.expectEqual(hit, h.host().resolve.?(h.host(), ball, audio, "HitSound", c.KE_SCRIPT_BORROW_ANYWHERE, &verdict));
    try testing.expectEqual(@as(c.ke_script_resolve, c.KE_SCRIPT_RESOLVE_FOUND), verdict);
}

test "a borrow reaching anywhere does not see a type nobody registered" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const ball = h.tree.create("Ball", 0);
    var verdict: c.ke_script_resolve = c.KE_SCRIPT_RESOLVE_FOUND;
    try testing.expectEqual(@as(c.ke_entity, c.KE_ENTITY_INVALID),
        h.host().resolve.?(h.host(), ball, c.KE_SCRIPT_TYPE_NONE, "", c.KE_SCRIPT_BORROW_ANYWHERE, &verdict));
    try testing.expectEqual(@as(c.ke_script_resolve, c.KE_SCRIPT_RESOLVE_NONE), verdict);
}

test "the nearest ancestor of the wanted type wins over a further one" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const field = try h.declare("pong.field", c.KE_SCRIPT_REACH_ANY);
    const outer = h.tree.create("Outer", 0);
    const inner = h.tree.create("Inner", outer);
    const leaf = h.tree.create("Leaf", inner);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expect(h.host().bind.?(h.host(), outer, field, &m1, null));
    try testing.expect(h.host().bind.?(h.host(), inner, field, &m2, null));

    try testing.expectEqual(inner, h.host().resolve.?(h.host(), leaf, field, "", c.KE_SCRIPT_BORROW_ANCESTOR, null));
}

test "a node is not its own ancestor" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const field = try h.declare("pong.field", c.KE_SCRIPT_REACH_ANY);
    const node = h.tree.create("Field", 0);
    var marker: u32 = 1;
    try testing.expect(h.host().bind.?(h.host(), node, field, &marker, null));

    try testing.expectEqual(@as(c.ke_entity, c.KE_ENTITY_INVALID), h.host().resolve.?(h.host(), node, field, "", c.KE_SCRIPT_BORROW_ANCESTOR, null));
}

test "creating and destroying a script host leaves no block allocated" {
    var h: Harness = undefined;
    try h.init();
    _ = try h.declare("LeakProbe", c.KE_SCRIPT_REACH_SELF);
    h.deinit();
    try heap.expectNoLeaks();
}

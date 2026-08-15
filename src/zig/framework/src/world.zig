
const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

const apply = @import("components_apply.zig");

/// Starting size of the apply registry; it doubles on demand, so this only
/// trades a little memory against a few early reallocs.
const apply_initial_capacity: u32 = 16;

const ApplyEntry = struct {
    cid: c.ke_component_id,
    fn_ptr: c.ke_component_apply_fn,
    fields: ?[*]const c.ke_component_field,
    field_count: u32,
};

const State = struct {
    scheduler: ?*c.ke_scheduler, // borrowed
    ecs: ?*c.ke_ecs, // borrowed
    runtime: ?*c.ke_runtime, // borrowed
    scene_tree: ?*c.ke_scene_tree, // borrowed
    project_root: [*c]const u8, // borrowed string
    logger: ?*c.ke_logger, // borrowed
    signal_bus: ?*c.ke_signal_bus, // borrowed

    apply_registry: ?[*]ApplyEntry,
    apply_count: u32,
    apply_capacity: u32,
};

const Block = struct {
    state: State,
    world: c.ke_world,
};

fn stateOf(self: *c.ke_world) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// The logger the world was built with, for plugin-internal diagnostics.
/// Not a vtable slot: it is this plugin talking to itself, not ABI surface.
pub fn loggerOf(self: *c.ke_world) ?*c.ke_logger {
    return stateOf(self).logger;
}

/// The signal bus the world was built with, for plugin-internal wiring.
/// Not a vtable slot, same reasoning as loggerOf.
pub fn signalBusOf(self: *c.ke_world) ?*c.ke_signal_bus {
    return stateOf(self).signal_bus;
}

fn worldEcs(self_in: ?*c.ke_world) callconv(.c) ?*c.ke_ecs {
    const self = self_in orelse return null;
    return stateOf(self).ecs;
}

fn worldRuntime(self_in: ?*c.ke_world) callconv(.c) ?*c.ke_runtime {
    const self = self_in orelse return null;
    return stateOf(self).runtime;
}

fn worldSceneTree(self_in: ?*c.ke_world) callconv(.c) ?*c.ke_scene_tree {
    const self = self_in orelse return null;
    return stateOf(self).scene_tree;
}

/// The entry for `cid`, appending an empty one when the component has none yet.
/// Both registration slots share it, so a component can carry a generated field
/// table and a callback for what the table cannot describe.
fn entryFor(s: *State, cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) ?*ApplyEntry {
    if (s.apply_registry) |reg| {
        for (reg[0..s.apply_count]) |*entry| {
            if (entry.cid == cid) return entry;
        }
    }

    if (s.apply_count == s.apply_capacity) {
        const cap = if (s.apply_capacity != 0) s.apply_capacity * 2 else apply_initial_capacity;
        const new_buf = heap.gpa.alloc(ApplyEntry, cap) catch {
            E.fail(out_error, .out_of_memory, "apply registry allocation failed", @src());
            return null;
        };
        if (s.apply_registry) |old| {
            @memcpy(new_buf[0..s.apply_count], old[0..s.apply_count]);
            heap.gpa.free(old[0..s.apply_capacity]);
        }
        s.apply_registry = new_buf.ptr;
        s.apply_capacity = cap;
    }

    const entry = &s.apply_registry.?[s.apply_count];
    entry.* = .{ .cid = cid, .fn_ptr = null, .fields = null, .field_count = 0 };
    s.apply_count += 1;
    return entry;
}

fn worldRegisterComponentApply(
    self_in: ?*c.ke_world,
    cid: c.ke_component_id,
    apply_fn: c.ke_component_apply_fn,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or apply_fn == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const entry = entryFor(stateOf(self), cid, out_error) orelse return false;
    entry.fn_ptr = apply_fn;
    return true;
}

fn worldRegisterComponentFields(
    self_in: ?*c.ke_world,
    cid: c.ke_component_id,
    fields: [*c]const c.ke_component_field,
    field_count: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or fields == null or field_count == 0) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const entry = entryFor(stateOf(self), cid, out_error) orelse return false;
    entry.fields = fields;
    entry.field_count = field_count;
    return true;
}

fn worldGetComponentFields(
    self_in: ?*c.ke_world,
    cid: c.ke_component_id,
    out_count: [*c]u32,
) callconv(.c) [*c]const c.ke_component_field {
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

fn worldGetComponentApply(
    self_in: ?*c.ke_world,
    cid: c.ke_component_id,
) callconv(.c) c.ke_component_apply_fn {
    const self = self_in orelse return null;
    if (self.handle == null) return null;
    const s = stateOf(self);
    const reg = s.apply_registry orelse return null;
    for (reg[0..s.apply_count]) |entry| {
        if (entry.cid == cid) return entry.fn_ptr;
    }
    return null;
}

fn worldDestroy(self_in: ?*c.ke_world) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.apply_registry) |reg| heap.gpa.free(reg[0..s.apply_capacity]);
    heap.gpa.destroy(@as(*Block, @fieldParentPtr("state", s)));
}

/// Registers a built-in component with the ecs (reusing an existing
/// registration when the name is already known) and wires up its apply callback.
fn registerBuiltin(
    world: *c.ke_world,
    e: *c.ke_ecs,
    name: [*c]const u8,
    size: usize,
    apply_fn: c.ke_component_apply_fn,
    fields: ?[*]const c.ke_component_field,
    field_count: u32,
) void {
    var meta: c.ke_component_meta = undefined;
    const cid = if (e.component_lookup.?(e, name, &meta, null))
        meta.cid
    else
        e.component_register.?(e, name, size, null);
    if (fields) |f| _ = world.register_component_fields.?(world, cid, f, field_count, null);
    if (apply_fn != null) _ = world.register_component_apply.?(world, cid, apply_fn, null);
}

export fn ke_world_create(
    params_in: ?*const c.ke_world_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_world_handle {
    const null_handle = std.mem.zeroes(c.ke_world_handle);

    const params = params_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null_handle;
    };
    if (params.ecs == null or params.runtime == null) {
        E.fail(out_error, .invalid_argument, "ecs and runtime are required", @src());
        return null_handle;
    }

    const block = heap.gpa.create(Block) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    block.* = std.mem.zeroes(Block);

    const state = &block.state;
    const world = &block.world;

    state.scheduler = params.scheduler;
    state.ecs = params.ecs;
    state.runtime = params.runtime;
    state.scene_tree = params.scene_tree;
    state.project_root = params.project_root;
    state.logger = params.logger;
    state.signal_bus = params.signal_bus;

    world.handle = state;
    world.ecs = worldEcs;
    world.runtime = worldRuntime;
    world.scene_tree = worldSceneTree;
    world.register_component_fields = worldRegisterComponentFields;
    world.get_component_fields = worldGetComponentFields;
    world.register_component_apply = worldRegisterComponentApply;
    world.get_component_apply = worldGetComponentApply;

    const e = params.ecs.?;
    registerBuiltin(world, e, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component),
        apply.ke_framework_apply_transform,
        &c.ke_transform_component_fields, c.ke_transform_component_fields.len);
    registerBuiltin(world, e, c.KE_COMPONENT_NAME_TRANSFORM_2D, @sizeOf(c.ke_transform2d_component),
        apply.ke_framework_apply_transform2d,
        &c.ke_transform2d_component_fields, c.ke_transform2d_component_fields.len);
    registerBuiltin(world, e, c.KE_COMPONENT_NAME_WORLD_TRANSFORM, @sizeOf(c.ke_world_transform_component),
        null, null, 0);

    return .{ .ref = world, .destroy = worldDestroy };
}

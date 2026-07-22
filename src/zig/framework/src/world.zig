// ke_world impl — default framework aggregator. Holds ecs+runtime+scene_tree
// handed over by the host on create, and the component-apply registry the
// scene loader consults.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

const apply = @import("components_apply.zig");

/// Starting size of the apply registry; it doubles on demand, so this only
/// trades a little memory against a few early reallocs.
const apply_initial_capacity: u32 = 16;

// A tiny linear array of (cid, fn) pairs. The scene loader is the only consumer
// today and lookups happen at scene-load time, not per frame, so a linear scan
// over the typical 6-20 entries is fine. Past ~64 this wants a hash.
const ApplyEntry = struct {
    cid: c.ke_component_id,
    fn_ptr: c.ke_component_apply_fn,
};

const State = struct {
    scheduler: ?*c.ke_scheduler, // borrowed
    ecs: ?*c.ke_ecs, // borrowed
    runtime: ?*c.ke_runtime, // borrowed
    scene_tree: ?*c.ke_scene_tree, // borrowed
    project_root: [*c]const u8, // borrowed string
    logger: ?*c.ke_logger, // borrowed

    apply_registry: ?[*]ApplyEntry,
    apply_count: u32,
    apply_capacity: u32,
};

// State and vtable live in one allocation, so freeing the state frees both.
const Block = struct {
    state: State,
    world: c.ke_world,
};

fn stateOf(self: *c.ke_world) *State {
    return @ptrCast(@alignCast(self.handle));
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
    const s = stateOf(self);

    // Replace-if-exists: registering the same cid twice updates the function.
    if (s.apply_registry) |reg| {
        for (reg[0..s.apply_count]) |*entry| {
            if (entry.cid == cid) {
                entry.fn_ptr = apply_fn;
                return true;
            }
        }
    }

    if (s.apply_count == s.apply_capacity) {
        const cap = if (s.apply_capacity != 0) s.apply_capacity * 2 else apply_initial_capacity;
        const new_buf = heap.gpa.alloc(ApplyEntry, cap) catch {
            E.fail(out_error, .out_of_memory, "apply registry allocation failed", @src());
            return false;
        };
        if (s.apply_registry) |old| {
            @memcpy(new_buf[0..s.apply_count], old[0..s.apply_count]);
            // Released at the capacity it was allocated with, which the state
            // still holds until the new one is published below.
            heap.gpa.free(old[0..s.apply_capacity]);
        }
        s.apply_registry = new_buf.ptr;
        s.apply_capacity = cap;
    }

    s.apply_registry.?[s.apply_count] = .{ .cid = cid, .fn_ptr = apply_fn };
    s.apply_count += 1;
    return true;
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
    // ecs, runtime and scene_tree are borrowed: whoever created them destroys
    // them after world->destroy(). The state sits at the head of the block, so
    // freeing it releases the vtable too.
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
) void {
    var meta: c.ke_component_meta = undefined;
    const cid = if (e.component_lookup.?(e, name, &meta, null))
        meta.cid
    else
        e.component_register.?(e, name, size);
    _ = world.register_component_apply.?(world, cid, apply_fn, null);
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

    world.handle = state;
    world.ecs = worldEcs;
    world.runtime = worldRuntime;
    world.scene_tree = worldSceneTree;
    world.register_component_apply = worldRegisterComponentApply;
    world.get_component_apply = worldGetComponentApply;

    // Register the framework's built-in component vocabulary and wire each
    // component's apply callback, so the scene loader works out of the box.
    // scene_tree already registers transform/hierarchy/name; the rest are
    // first-touch here. The host pays this schema setup once per world.
    const e = params.ecs.?;
    registerBuiltin(world, e, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component), apply.ke_framework_apply_transform);
    registerBuiltin(world, e, c.KE_COMPONENT_NAME_CAMERA, @sizeOf(c.ke_camera_component), apply.ke_framework_apply_camera);
    registerBuiltin(world, e, c.KE_COMPONENT_NAME_MESH, @sizeOf(c.ke_mesh_component), apply.ke_framework_apply_mesh);
    registerBuiltin(world, e, c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, @sizeOf(c.ke_directional_light_component), apply.ke_framework_apply_directional_light);
    registerBuiltin(world, e, c.KE_COMPONENT_NAME_POINT_LIGHT, @sizeOf(c.ke_point_light_component), apply.ke_framework_apply_point_light);
    registerBuiltin(world, e, c.KE_COMPONENT_NAME_SPOT_LIGHT, @sizeOf(c.ke_spot_light_component), apply.ke_framework_apply_spot_light);

    return .{ .ref = world, .destroy = worldDestroy };
}

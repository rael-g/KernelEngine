//! Keeps the world matrix of every entity equal to its local matrix composed with its parent's
//! world matrix, through one runtime system registered by the scene hierarchy factory.

const std = @import("std");

const c = @import("c");
const R = @import("result").Result(c, .{});
const log = std.log.scoped(.framework);
const heap = @import("heap");
const mat4 = @import("mat4.zig");

/// Created by `ke_scene_hierarchy_create`, owned by the handle it returns, and freed by
/// `vtDestroy`. The runtime keeps its address as the user data of `propagateSystem`, so the record
/// must not be moved or copied: `queries` and `access` are pointed at from the registration, and
/// the query's terms point into `queries_terms`.
const State = struct {
    ecs: *c.ke_ecs,
    transform_cid: c.ke_component_id,
    transform2d_cid: c.ke_component_id,
    world_transform_cid: c.ke_component_id,
    hierarchy_cid: c.ke_component_id,

    order: std.ArrayList(c.ke_entity) = .empty,
    stack: std.ArrayList(c.ke_entity) = .empty,

    queries_terms: [1]c.ke_component_access = undefined,

    queries: [1]c.ke_query_decl = undefined,
    access: [4]c.ke_component_access = undefined,
};

fn hierarchyOf(s: *State, e: c.ke_entity) ?*const c.ke_hierarchy_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.hierarchy_cid)));
}

fn transformOf(s: *State, e: c.ke_entity) ?*const c.ke_transform_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.transform_cid)));
}

fn transform2dOf(s: *State, e: c.ke_entity) ?*const c.ke_transform2d_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.transform2d_cid)));
}

fn worldTransformOf(s: *State, e: c.ke_entity) ?*c.ke_world_transform_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.world_transform_cid)));
}

fn identityMatrix() c.ke_mat4 {
    var m: c.ke_mat4 = undefined;
    for (&m.m, 0..) |*cell, i| cell.* = if (i % 5 == 0) 1.0 else 0.0;
    return m;
}

/// Appends the subtree below the root to `order` through `stack`, without recursion. A parent is
/// appended before its children. An allocation failure is not reported: the entities
/// it prevents from being pushed or appended are left out of `order`.
fn pushSubtree(s: *State, root: c.ke_entity) void {
    s.stack.append(heap.gpa, root) catch return;
    while (s.stack.pop()) |entity| {
        s.order.append(heap.gpa, entity) catch return;
        const h = hierarchyOf(s, entity) orelse continue;
        var child = h.first_child;
        while (child != c.KE_ENTITY_INVALID) {
            s.stack.append(heap.gpa, child) catch break;
            child = if (hierarchyOf(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
        }
    }
}

/// Runs at the start of every tick, before any world matrix is written, so `order` reflects the
/// parent links of that tick.
fn flatten(s: *State, ctx: ?*c.ke_system_ctx) void {
    s.order.clearRetainingCapacity();

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    if (segs == null) return;

    for (0..segc) |si| {
        const seg = segs[si];
        const hs: [*]const c.ke_hierarchy_component = @ptrCast(@alignCast(seg.columns[0].?));
        for (0..seg.count) |i| {
            if (hs[i].parent == c.KE_ENTITY_INVALID) pushSubtree(s, seg.entities[i]);
        }
    }
}

/// The system registered by `ke_scene_hierarchy_create`, run once per tick in the post-update
/// phase. It rebuilds `order` with `flatten`, then makes a single pass over it, so that a parent's
/// world matrix is final before any child reads it and no recursion is needed. An entity without
/// a world transform is passed over; one without a parent, or whose parent has no world
/// transform, composes with the identity. Always succeeds and reports nothing. Without a `State` it
/// does nothing.
fn propagateSystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) c.ke_result {
    const s: *State = @ptrCast(@alignCast(user orelse return R.ok));
    flatten(s, ctx);

    const identity = identityMatrix();

    for (s.order.items) |entity| {
        const w = worldTransformOf(s, entity) orelse continue;
        const h = hierarchyOf(s, entity);

        const parent_world = blk: {
            const hier = h orelse break :blk &identity;
            if (hier.parent == c.KE_ENTITY_INVALID) break :blk &identity;
            const pw = worldTransformOf(s, hier.parent) orelse break :blk &identity;
            break :blk &pw.matrix;
        };

        var local = identity;
        if (transformOf(s, entity)) |t| {
            mat4.fromTransform(&local, &t.position, &t.rotation, &t.scale);
        } else if (transform2dOf(s, entity)) |t2| {
            mat4.fromTransform2d(&local, &t2.position, t2.rotation, &t2.scale, t2.depth);
        }
        mat4.mul(&w.matrix, &local, parent_world);
    }
    return R.ok;
}

/// The destroy of the handle. Frees the `State`. The runtime keeps the `State` as the user data of
/// the system and nothing here unregisters it, so the handle must be destroyed only after the
/// runtime has finished ticking.
fn vtDestroy(self_in: ?*c.ke_scene_hierarchy) callconv(.c) void {
    const self = self_in orelse return;
    const s: *State = @ptrCast(@alignCast(self));
    s.order.deinit(heap.gpa);
    s.stack.deinit(heap.gpa);
    heap.gpa.destroy(s);
}

/// Factory. Registers the system `scene.propagate_transforms` on the runtime, in the post-update
/// phase, and writes a handle that owns the `State`. A null argument fails as an invalid argument;
/// a transform, 2D transform, world transform or hierarchy component not registered on the ecs
/// fails as not found; a failed allocation fails as out of memory; a refused system registration
/// fails with the runtime's code. Each leaves the handle zeroed.
export fn ke_scene_hierarchy_create(
    runtime_in: ?*c.ke_runtime,
    ecs_in: ?*c.ke_ecs,
    out_hierarchy: ?*c.ke_scene_hierarchy_handle,
) callconv(.c) c.ke_result {
    const out = out_hierarchy orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(c.ke_scene_hierarchy_handle);
    const runtime = runtime_in orelse return R.code(error.InvalidArgument);
    const ecs = ecs_in orelse return R.code(error.InvalidArgument);
    out.* = create(runtime, ecs) catch |err| return R.code(err);
    return R.ok;
}

fn create(runtime: *c.ke_runtime, ecs: *c.ke_ecs) R.Error!c.ke_scene_hierarchy_handle {
    var transform_meta: c.ke_component_meta = undefined;
    var transform2d_meta: c.ke_component_meta = undefined;
    var world_transform_meta: c.ke_component_meta = undefined;
    var hierarchy_meta: c.ke_component_meta = undefined;
    if (!ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_TRANSFORM, &transform_meta) or
        !ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_TRANSFORM2D, &transform2d_meta) or
        !ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_WORLD_TRANSFORM, &world_transform_meta) or
        !ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_HIERARCHY, &hierarchy_meta))
    {
        log.warn("scene hierarchy: the scene tree components are not registered on this ecs", .{});
        return error.NotFound;
    }

    const s = try heap.gpa.create(State);
    errdefer heap.gpa.destroy(s);
    s.* = .{
        .ecs = ecs,
        .transform_cid = transform_meta.cid,
        .transform2d_cid = transform2d_meta.cid,
        .world_transform_cid = world_transform_meta.cid,
        .hierarchy_cid = hierarchy_meta.cid,
    };
    s.queries_terms = .{ .{ .cid = s.hierarchy_cid, .access = c.KE_ACCESS_READ } };
    s.queries = .{ .{ .terms = &s.queries_terms[0], .term_count = 1 } };

    s.access = .{
        .{ .cid = s.hierarchy_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = s.transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = s.transform2d_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = s.world_transform_cid, .access = c.KE_ACCESS_WRITE },
    };

    var propagate = std.mem.zeroes(c.ke_runtime_system_params);
    propagate.name = "scene.propagate_transforms";
    propagate.phase = c.KE_PHASE_POST_UPDATE;
    propagate.queries = &s.queries;
    propagate.query_count = s.queries.len;
    propagate.access_list = &s.access;
    propagate.access_count = s.access.len;
    propagate.user_data = s;
    propagate.execute = propagateSystem;

    var system_id: c.ke_system_id = 0;
    try R.check(runtime.register_system.?(runtime, &propagate, &system_id));

    return .{ .ref = @ptrCast(s), .destroy = vtDestroy };
}

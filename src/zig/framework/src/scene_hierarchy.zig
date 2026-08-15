
const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");
const mat4 = @import("mat4.zig");

const E = @import("kerror").Errors(c);

const State = struct {
    ecs: *c.ke_ecs,
    transform_cid: c.ke_component_id,
    transform2d_cid: c.ke_component_id,
    world_transform_cid: c.ke_component_id,
    hierarchy_cid: c.ke_component_id,

    order: std.ArrayList(c.ke_entity) = .empty,
    stack: std.ArrayList(c.ke_entity) = .empty,

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

/// Appends `root` and its whole subtree, parents first. Iterative: children are
/// pushed onto the stack and popped later, which reproduces a depth-first order
/// without the call depth.
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

fn flatten(s: *State, ctx: ?*c.ke_system_ctx) void {
    s.order.clearRetainingCapacity();

    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &segc);
    if (segs == null) return;

    for (0..segc) |si| {
        const seg = segs[si];
        const hs: [*]const c.ke_hierarchy_component = @ptrCast(@alignCast(seg.columns[0].?));
        for (0..seg.count) |i| {
            if (hs[i].parent == c.KE_ENTITY_INVALID) pushSubtree(s, seg.entities[i]);
        }
    }
}

/// Flattening and propagation are one system on purpose. Split in two they would
/// declare no conflicting access — a reader of hierarchy and a writer of
/// transforms — so the wave builder would be free to run them side by side, and
/// the second would read the order buffer while the first was still filling it.
/// The buffer is private scratch that nothing else consumes, so there is nothing
/// to gain from exposing the split and a race to lose.
fn propagateSystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const s: *State = @ptrCast(@alignCast(user orelse return));
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
}

fn vtDestroy(self_in: ?*c.ke_scene_hierarchy) callconv(.c) void {
    const self = self_in orelse return;
    const s: *State = @ptrCast(@alignCast(self));
    s.order.deinit(heap.gpa);
    s.stack.deinit(heap.gpa);
    heap.gpa.destroy(s);
}

export fn ke_scene_hierarchy_create(
    runtime_in: ?*c.ke_runtime,
    ecs_in: ?*c.ke_ecs,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_scene_hierarchy_handle {
    const empty = std.mem.zeroes(c.ke_scene_hierarchy_handle);
    const runtime = runtime_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return empty;
    };
    const ecs = ecs_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return empty;
    };

    var transform_meta: c.ke_component_meta = undefined;
    var transform2d_meta: c.ke_component_meta = undefined;
    var world_transform_meta: c.ke_component_meta = undefined;
    var hierarchy_meta: c.ke_component_meta = undefined;
    if (!ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_TRANSFORM, &transform_meta, null) or
        !ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_TRANSFORM_2D, &transform2d_meta, null) or
        !ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_WORLD_TRANSFORM, &world_transform_meta, null) or
        !ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_HIERARCHY, &hierarchy_meta, null))
    {
        E.fail(out_error, .not_found, "scene_tree components are not registered on this ecs", @src());
        return empty;
    }

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return empty;
    };
    s.* = .{
        .ecs = ecs,
        .transform_cid = transform_meta.cid,
        .transform2d_cid = transform2d_meta.cid,
        .world_transform_cid = world_transform_meta.cid,
        .hierarchy_cid = hierarchy_meta.cid,
    };

    s.queries = std.mem.zeroes([1]c.ke_query_decl);
    s.queries[0].terms[0] = .{ .cid = s.hierarchy_cid, .access = c.KE_ACCESS_READ };
    s.queries[0].term_count = 1;

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

    if (runtime.register_system.?(runtime, &propagate, out_error) == 0) {
        heap.gpa.destroy(s);
        return empty;
    }

    return .{ .ref = @ptrCast(s), .destroy = vtDestroy };
}

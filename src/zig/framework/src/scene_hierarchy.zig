//! Keeps the world matrix of every entity equal to its local matrix composed with its parent's
//! world matrix, through one schedule system the scene hierarchy module registers when created.

const abi_framework_components = @import("abi_framework_components");
const abi_spatial_contract = @import("abi_spatial_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_part = @import("abi_part");
const abi_math = @import("abi_math");
const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const abi_spatial = @import("abi_spatial");
const R = @import("result").Result(.{});
const log = std.log.scoped(.framework);
const heap = @import("heap");
const mat4 = @import("mat4.zig");

/// Created by `ke_scene_hierarchy_create`, owned by the owner it returns, and freed by `ownerDestroy`,
/// which unregisters first. `schedule` keeps its address as the user data of `propagateSystem`, so the
/// record must not be moved or copied: `queries` and `access` are pointed at from the registration,
/// and the query's terms point into `queries_terms`.
const State = struct {
    schedule: *abi_schedule.c.ke_schedule,
    system: abi_schedule.c.ke_schedule_system_id = 0,
    set: [1]abi_schedule.c.ke_schedule_set_id = .{0},
    ecs: *abi_ecs.c.ke_ecs,
    transform_cid: abi_asset_resolver.c.ke_component_id,
    transform2d_cid: abi_asset_resolver.c.ke_component_id,
    world_transform_cid: abi_asset_resolver.c.ke_component_id,
    hierarchy_cid: abi_asset_resolver.c.ke_component_id,

    order: std.ArrayList(abi_asset_resolver.c.ke_entity) = .empty,
    stack: std.ArrayList(abi_asset_resolver.c.ke_entity) = .empty,

    queries_terms: [1]abi_ecs.c.ke_ecs_query_term = undefined,

    queries: [1]abi_ecs.c.ke_ecs_query_desc = undefined,
    access: [4]abi_ecs.c.ke_ecs_query_term = undefined,
};

fn hierarchyOf(s: *State, e: abi_asset_resolver.c.ke_entity) ?*const abi_framework_components.c.ke_hierarchy_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.hierarchy_cid)));
}

fn transformOf(s: *State, e: abi_asset_resolver.c.ke_entity) ?*const abi_spatial.c.ke_transform_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.transform_cid)));
}

fn transform2dOf(s: *State, e: abi_asset_resolver.c.ke_entity) ?*const abi_spatial.c.ke_transform2d_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.transform2d_cid)));
}

fn worldTransformOf(s: *State, e: abi_asset_resolver.c.ke_entity) ?*abi_spatial.c.ke_world_transform_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.world_transform_cid)));
}

fn identityMatrix() abi_math.c.ke_mat4 {
    var m: abi_math.c.ke_mat4 = undefined;
    for (&m.m, 0..) |*cell, i| cell.* = if (i % 5 == 0) 1.0 else 0.0;
    return m;
}

/// Appends the subtree below the root to `order` through `stack`, without recursion. A parent is
/// appended before its children. An allocation failure is not reported: the entities
/// it prevents from being pushed or appended are left out of `order`.
fn pushSubtree(s: *State, root: abi_asset_resolver.c.ke_entity) void {
    s.stack.append(heap.gpa, root) catch return;
    while (s.stack.pop()) |entity| {
        s.order.append(heap.gpa, entity) catch return;
        const h = hierarchyOf(s, entity) orelse continue;
        var child = h.first_child;
        while (child != abi_ecs.c.KE_ENTITY_INVALID) {
            s.stack.append(heap.gpa, child) catch break;
            child = if (hierarchyOf(s, child)) |ch| ch.next_sibling else abi_ecs.c.KE_ENTITY_INVALID;
        }
    }
}

/// Runs at the start of every tick, before any world matrix is written, so `order` reflects the
/// parent links of that tick.
fn flatten(s: *State, ctx: ?*abi_schedule.c.ke_schedule_ctx) void {
    s.order.clearRetainingCapacity();

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    if (segs == null) return;

    for (0..segc) |si| {
        const seg = segs.?[si];
        const hs: [*]const abi_framework_components.c.ke_hierarchy_component = @ptrCast(@alignCast(seg.columns.?[0].?));
        for (0..seg.count) |i| {
            if (hs[i].parent == abi_ecs.c.KE_ENTITY_INVALID) pushSubtree(s, seg.entities.?[i]);
        }
    }
}

/// The system registered by `ke_scene_hierarchy_create`, run once per tick in the post-update
/// phase. It rebuilds `order` with `flatten`, then makes a single pass over it, so that a parent's
/// world matrix is final before any child reads it and no recursion is needed. An entity without
/// a world transform is passed over; one without a parent, or whose parent has no world
/// transform, composes with the identity. Always succeeds and reports nothing. Without a `State` it
/// does nothing.
fn propagateSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const s: *State = @ptrCast(@alignCast(user orelse return R.ok));
    flatten(s, ctx);

    const identity = identityMatrix();

    for (s.order.items) |entity| {
        const w = worldTransformOf(s, entity) orelse continue;
        const h = hierarchyOf(s, entity);

        const parent_world = blk: {
            const hier = h orelse break :blk &identity;
            if (hier.parent == abi_ecs.c.KE_ENTITY_INVALID) break :blk &identity;
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

/// The owner's destroy: unregisters the system and frees the `State`.
fn ownerDestroy(ref: ?*anyopaque) callconv(.c) void {
    const s: *State = @ptrCast(@alignCast(ref orelse return));
    _ = s.schedule.unregister_system.?(s.schedule, s.system);
    s.order.deinit(heap.gpa);
    s.stack.deinit(heap.gpa);
    heap.gpa.destroy(s);
}

/// Factory. Resolves the scene tree components, registers `scene.propagate_transforms` in `post_update_set`
/// of `post_update`, and writes an owner of the `State`. A null argument fails as an invalid argument; a
/// transform, 2D transform, world transform or hierarchy component not registered on the ecs fails as not
/// found; a failed allocation fails as out of memory; a refused system fails with the schedule's code. Each
/// leaves the owner zeroed.
export fn ke_scene_hierarchy_create(
    ecs_in: ?*abi_ecs.c.ke_ecs,
    post_update_in: ?*abi_schedule.c.ke_schedule,
    post_update_set: abi_schedule.c.ke_schedule_set_id,
    out_module: ?*abi_part.c.ke_owner,
) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_part.c.ke_owner);
    const ecs = ecs_in orelse return R.code(error.InvalidArgument);
    const post_update = post_update_in orelse return R.code(error.InvalidArgument);
    out.* = create(ecs, post_update, post_update_set) catch |err| return R.code(err);
    return R.ok;
}

fn create(ecs: *abi_ecs.c.ke_ecs, post_update: *abi_schedule.c.ke_schedule, post_update_set: abi_schedule.c.ke_schedule_set_id) R.Error!abi_part.c.ke_owner {
    var transform_meta: abi_ecs.c.ke_component_meta = undefined;
    var transform2d_meta: abi_ecs.c.ke_component_meta = undefined;
    var world_transform_meta: abi_ecs.c.ke_component_meta = undefined;
    var hierarchy_meta: abi_ecs.c.ke_component_meta = undefined;
    if (!ecs.component_lookup.?(ecs, abi_spatial_contract.c.KE_COMPONENT_NAME_TRANSFORM, &transform_meta) or
        !ecs.component_lookup.?(ecs, abi_spatial_contract.c.KE_COMPONENT_NAME_TRANSFORM2D, &transform2d_meta) or
        !ecs.component_lookup.?(ecs, abi_spatial_contract.c.KE_COMPONENT_NAME_WORLD_TRANSFORM, &world_transform_meta) or
        !ecs.component_lookup.?(ecs, abi_framework_components.c.KE_COMPONENT_NAME_HIERARCHY, &hierarchy_meta))
    {
        log.warn("scene hierarchy: the scene tree components are not registered on this ecs", .{});
        return error.NotFound;
    }

    const s = try heap.gpa.create(State);
    errdefer heap.gpa.destroy(s);
    s.* = .{
        .schedule = post_update,
        .set = .{post_update_set},
        .ecs = ecs,
        .transform_cid = transform_meta.cid,
        .transform2d_cid = transform2d_meta.cid,
        .world_transform_cid = world_transform_meta.cid,
        .hierarchy_cid = hierarchy_meta.cid,
    };
    s.queries_terms = .{ .{ .component = s.hierarchy_cid, .access = abi_ecs.c.KE_ECS_ACCESS_READ } };
    s.queries = .{ .{ .terms = s.queries_terms[0..].ptr, .term_count = 1 } };
    s.access = .{
        .{ .component = s.hierarchy_cid, .access = abi_ecs.c.KE_ECS_ACCESS_READ },
        .{ .component = s.transform_cid, .access = abi_ecs.c.KE_ECS_ACCESS_READ },
        .{ .component = s.transform2d_cid, .access = abi_ecs.c.KE_ECS_ACCESS_READ },
        .{ .component = s.world_transform_cid, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE },
    };
    const propagate: abi_schedule.c.ke_schedule_system_desc = .{
        .name = "scene.propagate_transforms",
        .user_data = s,
        .execute = propagateSystem,
        .queries = &s.queries,
        .query_count = s.queries.len,
        .access = &s.access,
        .access_count = s.access.len,
        .sets = &s.set,
        .set_count = 1,
    };
    const registered = post_update.register_system.?(post_update, &propagate, &s.system);
    if (registered != R.ok) {
        log.warn("scene hierarchy: the schedule refused the system", .{});
        try R.check(registered);
    }
    return .{ .ref = s, .destroy = ownerDestroy };
}

const testing = std.testing;
const zsub = @import("zsub");

fn lookupFound(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_lookup)) bool {
    const meta = args[2] orelse return false;
    meta.* = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    meta.cid = 1;
    return true;
}

test "creating registers the system, and destroying unregisters it" {
    var ecs: zsub.For(abi_ecs.c.ke_ecs) = undefined;
    try ecs.init();
    defer ecs.deinit();
    _ = ecs.when(.component_lookup).does(lookupFound);
    var rt: zsub.For(abi_schedule.c.ke_schedule) = undefined;
    try rt.init();
    defer rt.deinit();
    _ = rt.when(.register_system).writesFresh(2);
    var h: abi_part.c.ke_owner = undefined;
    try R.check(ke_scene_hierarchy_create(ecs.api(), rt.api(), 3, &h));
    h.destroy.?(h.ref);
    try rt.received(.register_system).times(1);
    try rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_schedule.c.ke_schedule_system_id, 0))).never();
    try rt.received(.unregister_system).sameAs(rt.received(.register_system));
}

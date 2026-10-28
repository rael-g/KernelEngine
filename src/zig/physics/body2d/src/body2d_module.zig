//! Keeps the entity components of 2D bodies and colliders in agreement with a `ke_physics_2d`
//! world, through two fixed-post-update-phase systems. It also exports the set of those components
//! a scene file can author.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_physics_body2d").logFn };

const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_physics = @import("abi_physics");
const abi_physics_body2d_factory = @import("abi_physics_body2d_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");

const heap = @import("heap");
var gpa = heap.gpa;

/// A body the module created, and the update in which its entity was last seen holding it.
const Tracked = struct {
    body: abi_physics.ke_body_2d,
    seen: u64,
};

/// The state behind the handle `ke_physics_body2d_module_create` returns, owned by that handle.
/// The query declarations point into this struct's own term arrays, so its address must stay
/// fixed while the two systems are registered. `physics` is borrowed from the params. `tracked` holds every body the module created, by entity, and
/// `update` counts the body system's runs, so a body whose entity no longer holds it is found.
const Module = struct {
    physics: *abi_physics.ke_physics_2d,
    runtime: *abi_runtime.ke_runtime,
    tree: *abi_framework.ke_scene_tree,
    body_generation: u64 = 0,
    attempt: ?Attempt = null,
    body_system: abi_runtime.ke_system_id = 0,
    collider_system: abi_runtime.ke_system_id = 0,
    tracked: std.AutoHashMapUnmanaged(abi_ecs.ke_entity, Tracked) = .empty,
    update: u64 = 0,
    body_queries_terms: [2]abi_runtime.ke_component_access = undefined,
    body_queries: [1]abi_runtime.ke_query_decl = undefined,
    collider_queries_terms: [4]abi_runtime.ke_component_access = undefined,
    collider_queries: [3]abi_runtime.ke_query_decl = undefined,
};

/// What the collider system last tried to attach against: the tree's hierarchy generation, the
/// module's body generation and the number of colliders. An unattached collider is retried only
/// once one of them differs.
const Attempt = struct { hierarchy: u64, bodies: u64, colliders: usize };

fn moduleOf(user: ?*anyopaque) *Module {
    return @ptrCast(@alignCast(user.?));
}

const log = std.log.scoped(.physics_body2d);
const R = @import("result").Result(.{});

/// The fixed-post-update-phase system that reconciles every body with its component and transform,
/// in this order: a component with no body gets one at its transform's position and rotation; a
/// transform or a velocity that differs from the world's pushes it in; the world steps by `dt`;
/// every body's state is then written back, its velocities into its component and its position and
/// angle into its transform. A body created here is therefore simulated in the same update. The
/// body type, gravity scale and fixed rotation are read only when the body is created. A failed
/// creation, or a body the module cannot record, leaves the component without a body, to be retried
/// on the next update; nothing is written to the error output and the system still returns true.
/// Before the step, a recorded body whose entity no longer holds it, destroyed or stripped of the
/// component, is destroyed.
fn bodySystem(ctx: ?*abi_runtime.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) abi_result.ke_result {
    const m = moduleOf(user);
    const p = m.physics;
    m.update += 1;

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);

    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const bodies: [*c]abi_physics.ke_body2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        const tcs0: [*c]abi_spatial.ke_transform2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[1]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            const b = &bodies[i];
            const pose = tcs0[i];
            if (b.body == abi_physics.KE_BODY_2D_INVALID) {
                if (p.create_body.?(p, b.type, pose.position.x, pose.position.y, &b.body) != R.ok) continue;
                m.tracked.put(gpa, segs.?[s].entities.?[i], .{ .body = b.body, .seen = m.update }) catch {
                    p.destroy_body.?(p, b.body);
                    b.body = abi_physics.KE_BODY_2D_INVALID;
                    continue;
                };
                m.body_generation +%= 1;
                p.set_body_position.?(p, b.body, pose.position.x, pose.position.y, pose.rotation);
                p.set_body_velocity.?(p, b.body, b.velocity.x, b.velocity.y);
                p.set_body_fixed_rotation.?(p, b.body, b.fixed_rotation);
                p.set_body_gravity_scale.?(p, b.body, b.gravity_scale);
                log.info(
                    "body on entity {d}: type={d} pos=({d:.3},{d:.3}) angle={d:.4} scale=({d:.3},{d:.3})",
                    .{ segs.?[s].entities.?[i], b.type, pose.position.x, pose.position.y, pose.rotation, pose.scale.x, pose.scale.y });
                continue;
            }

            if (m.tracked.getPtr(segs.?[s].entities.?[i])) |t| t.seen = m.update;

            var st: abi_physics.ke_body_state_2d = undefined;
            p.get_body_state.?(p, b.body, &st);
            if (pose.position.x != st.x or pose.position.y != st.y or pose.rotation != st.angle)
                p.set_body_position.?(p, b.body, pose.position.x, pose.position.y, pose.rotation);
            if (b.velocity.x != st.velocity_x or b.velocity.y != st.velocity_y)
                p.set_body_velocity.?(p, b.body, b.velocity.x, b.velocity.y);
        }
    }

    destroyUnseen(m);
    p.step.?(p, dt);

    s = 0;
    while (s < segc) : (s += 1) {
        const bodies: [*c]abi_physics.ke_body2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        const tcs: [*c]abi_spatial.ke_transform2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[1]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            const b = &bodies[i];
            if (b.body == abi_physics.KE_BODY_2D_INVALID) continue;

            var st: abi_physics.ke_body_state_2d = undefined;
            p.get_body_state.?(p, b.body, &st);

            b.velocity = .{ .x = st.velocity_x, .y = st.velocity_y };
            b.angular_velocity = st.angular_velocity;

            tcs[i].position = .{ .x = st.x, .y = st.y };
            tcs[i].rotation = st.angle;
        }
    }
    return R.ok;
}

/// Destroys every recorded body whose entity was not seen holding it in the current update, and
/// forgets it.
fn destroyUnseen(m: *Module) void {
    var it = m.tracked.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.seen == m.update) continue;
        m.physics.destroy_body.?(m.physics, entry.value_ptr.body);
        m.tracked.removeByPtr(entry.key_ptr);
        m.body_generation +%= 1;
        it = m.tracked.iterator();
    }
}

/// Counts the colliders and those still unattached, so `colliderSystem` can return before it
/// builds any index.
fn countColliders(ctx: ?*abi_runtime.ke_system_ctx) struct { total: usize, unattached: usize } {
    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    var total: usize = 0;
    var unattached: usize = 0;
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const cols: [*c]abi_physics.ke_collider2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        total += segs.?[s].count;
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            if (!cols[i].attached) unattached += 1;
        }
    }
    return .{ .total = total, .unattached = unattached };
}

/// The fixed-post-update-phase system that attaches fixtures to colliders. It returns at once when
/// every collider is attached, or when neither the tree's hierarchy generation, the module's body
/// generation nor the number of colliders moved since its last attempt, so a collider that resolved
/// to no body is retried, and its warning logged again, only once its ancestors or the bodies may
/// have changed. Otherwise each unattached collider is resolved to a body through `findBody` and
/// gets a fixture whose offset is its own transform's position. Its entity indexes are complete
/// before the first fixture is added, so an out-of-memory failure, reported through the error
/// output, leaves every collider unattached. A shape that resolves to no body, or whose fixture the
/// world refuses, is logged and stays unattached; neither is reported through the error output.
fn colliderSystem(ctx: ?*abi_runtime.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) abi_result.ke_result {
    _ = dt;
    const m = moduleOf(user);
    const p = m.physics;

    const counted = countColliders(ctx);
    if (counted.unattached == 0) return R.ok;
    const attempt: Attempt = .{ .hierarchy = m.tree.hierarchy_generation.?(m.tree), .bodies = m.body_generation, .colliders = counted.total };
    if (m.attempt) |last| if (std.meta.eql(last, attempt)) return R.ok;

    var parents = std.AutoHashMap(abi_ecs.ke_entity, abi_ecs.ke_entity).init(gpa);
    defer parents.deinit();
    var bodies = std.AutoHashMap(abi_ecs.ke_entity, abi_physics.ke_body_2d).init(gpa);
    defer bodies.deinit();

    var segc: usize = 0;
    var segs = ctx.?.view.?(ctx, 2, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const hs: [*c]abi_framework.ke_hierarchy_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            parents.put(segs.?[s].entities.?[i], hs[i].parent) catch {
                log.warn("collider pass: parent index allocation failed", .{});
                return R.code(error.OutOfMemory);
            };
        }
    }

    segs = ctx.?.view.?(ctx, 1, &segc);
    s = 0;
    while (s < segc) : (s += 1) {
        const bs: [*c]abi_physics.ke_body2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            if (bs[i].body == abi_physics.KE_BODY_2D_INVALID) continue;
            bodies.put(segs.?[s].entities.?[i], bs[i].body) catch {
                log.warn("collider pass: body index allocation failed", .{});
                return R.code(error.OutOfMemory);
            };
        }
    }

    segs = ctx.?.view.?(ctx, 0, &segc);
    s = 0;
    while (s < segc) : (s += 1) {
        const cols: [*c]abi_physics.ke_collider2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        const tcs: [*c]abi_spatial.ke_transform2d_component = @ptrCast(@alignCast(segs.?[s].columns.?[1]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            const col = &cols[i];
            if (col.attached) continue;

            const body = findBody(&parents, &bodies, segs.?[s].entities.?[i]) orelse {
                log.warn(
                    "shape on entity {d} resolves to no body; it will never collide", .{segs.?[s].entities.?[i]});
                continue;
            };

            const off = tcs[i].position;
            const angle = tcs[i].rotation;
            const filter = abi_physics.ke_collision_filter_2d{ .layer = col.layer, .mask = col.mask };
            const ok = R.ok == switch (col.kind) {
                abi_physics.KE_SHAPE_KIND_2D_CIRCLE => p.add_circle_fixture.?(p, body, col.radius, off.x, off.y, col.density, col.friction, col.restitution, &filter),
                else => p.add_box_fixture.?(p, body, col.half_extents.x, col.half_extents.y, off.x, off.y, angle, col.density, col.friction, col.restitution, &filter),
            };
            col.attached = ok;
            const shape_fmt = "shape on entity {d}: kind={d} half=({d:.3},{d:.3}) r={d:.3} off=({d:.3},{d:.3}) angle={d:.4} density={d:.3} friction={d:.3} restitution={d:.3} attached={}";
            const shape_args = .{ segs.?[s].entities.?[i], col.kind, col.half_extents.x, col.half_extents.y, col.radius, off.x, off.y, angle, col.density, col.friction, col.restitution, ok };
            if (ok) log.info(shape_fmt, shape_args) else log.err(shape_fmt, shape_args);
        }
    }
    m.attempt = attempt;
    return R.ok;
}

/// Walks the parent links above `start`, the shape's own entity, and returns the first body found
/// on that chain, or null when the chain ends first. The shape's own entity is not checked, only
/// its ancestors. The steps are bounded by the size of the parent index, so a cycle ends the walk.
fn findBody(
    parents: *std.AutoHashMap(abi_ecs.ke_entity, abi_ecs.ke_entity),
    bodies: *std.AutoHashMap(abi_ecs.ke_entity, abi_physics.ke_body_2d),
    start: abi_ecs.ke_entity,
) ?abi_physics.ke_body_2d {
    var e = parents.get(start) orelse return null;
    var steps: usize = 0;
    while (e != 0 and steps <= parents.count()) : (steps += 1) {
        if (bodies.get(e)) |b| return b;
        e = parents.get(e) orelse return null;
    }
    return null;
}

/// The `destroy` slot of the handle `ke_physics_body2d_module_create` returns, called by the owner
/// of that handle. Its two systems are unregistered from the runtime and the bodies the module
/// created are destroyed with it, so the runtime and the physics world it was given must still be
/// alive.
fn destroyHandle(self: ?*abi_physics_body2d_factory.ke_physics_body2d_module) callconv(.c) void {
    const m: *Module = @ptrCast(@alignCast(self orelse return));
    _ = m.runtime.unregister_system.?(m.runtime, m.collider_system);
    _ = m.runtime.unregister_system.?(m.runtime, m.body_system);
    var it = m.tracked.valueIterator();
    while (it.next()) |t| m.physics.destroy_body.?(m.physics, t.body);
    m.tracked.deinit(gpa);
    gpa.destroy(m);
}

/// Registers the component ids with the ECS, then the body system and the collider system, both in
/// the fixed post-update phase, after the fixed update where scripts write. Fails with invalid
/// argument for a missing argument, out of memory for a failed allocation, and the runtime's code
/// for a system it refuses. On success, the handle's `destroy` frees the module.
export fn ke_physics_body2d_module_create(
    params: ?*const abi_physics_body2d_factory.ke_physics_body2d_module_params,
    out_module: ?*abi_physics_body2d_factory.ke_physics_body2d_module_handle,
) callconv(.c) abi_result.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const pr = params orelse return R.code(error.InvalidArgument);
    out.* = create(pr) catch |err| {
        log.warn("creating the body2d module failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(pr: *const abi_physics_body2d_factory.ke_physics_body2d_module_params) R.Error!abi_physics_body2d_factory.ke_physics_body2d_module_handle {
    const rt = pr.runtime orelse return error.InvalidArgument;
    const ecs = pr.ecs orelse return error.InvalidArgument;
    const physics = pr.physics orelse return error.InvalidArgument;
    const tree = pr.scene_tree orelse return error.InvalidArgument;

    const m = gpa.create(Module) catch return error.OutOfMemory;
    errdefer gpa.destroy(m);
    m.* = .{ .physics = physics, .runtime = rt, .tree = tree };

    var body_cid: abi_ecs.ke_component_id = abi_ecs.KE_COMPONENT_INVALID;
    try R.check(ecs.*.component_register.?(ecs, &abi_ecs.ke_component_params{ .name = abi_physics.KE_COMPONENT_NAME_BODY2D, .size = @sizeOf(abi_physics.ke_body2d_component), .alignment = @alignOf(abi_physics.ke_body2d_component), .fields = &abi_physics.ke_body2d_component_fields, .field_count = abi_physics.ke_body2d_component_fields.len }, &body_cid));
    var transform_cid: abi_ecs.ke_component_id = abi_ecs.KE_COMPONENT_INVALID;
    try R.check(ecs.*.component_register.?(ecs, &abi_ecs.ke_component_params{ .name = abi_spatial.KE_COMPONENT_NAME_TRANSFORM2D, .size = @sizeOf(abi_spatial.ke_transform2d_component), .alignment = @alignOf(abi_spatial.ke_transform2d_component), .fields = &abi_spatial.ke_transform2d_component_fields, .field_count = abi_spatial.ke_transform2d_component_fields.len }, &transform_cid));
    var collider_cid: abi_ecs.ke_component_id = abi_ecs.KE_COMPONENT_INVALID;
    try R.check(ecs.*.component_register.?(ecs, &abi_ecs.ke_component_params{ .name = abi_physics.KE_COMPONENT_NAME_COLLIDER2D, .size = @sizeOf(abi_physics.ke_collider2d_component), .alignment = @alignOf(abi_physics.ke_collider2d_component), .fields = &abi_physics.ke_collider2d_component_fields, .field_count = abi_physics.ke_collider2d_component_fields.len }, &collider_cid));
    var hierarchy_cid: abi_ecs.ke_component_id = abi_ecs.KE_COMPONENT_INVALID;
    try R.check(ecs.*.component_register.?(ecs, &abi_ecs.ke_component_params{ .name = abi_framework.KE_COMPONENT_NAME_HIERARCHY, .size = @sizeOf(abi_framework.ke_hierarchy_component), .alignment = @alignOf(abi_framework.ke_hierarchy_component), .fields = null, .field_count = 0 }, &hierarchy_cid));

    const rd = abi_runtime.KE_ACCESS_READ;
    const wr = abi_runtime.KE_ACCESS_WRITE;
    m.body_queries_terms = .{ .{ .cid = body_cid, .access = wr }, .{ .cid = transform_cid, .access = wr } };
    m.body_queries = .{ .{ .terms = m.body_queries_terms[0..].ptr, .term_count = 2 } };

    var sp = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    sp.name = "physics.body2d";
    sp.phase = abi_runtime.KE_PHASE_FIXED_POST_UPDATE;
    sp.queries = &m.body_queries;
    sp.query_count = m.body_queries.len;
    sp.pinned_thread = 0;
    sp.user_data = m;
    sp.execute = bodySystem;
    m.body_system = 0;
    try R.check(rt.*.register_system.?(rt, &sp, &m.body_system));
    errdefer _ = rt.*.unregister_system.?(rt, m.body_system);
    m.collider_queries_terms = .{ .{ .cid = collider_cid, .access = wr }, .{ .cid = transform_cid, .access = rd }, .{ .cid = body_cid, .access = rd }, .{ .cid = hierarchy_cid, .access = rd } };
    m.collider_queries = .{ .{ .terms = m.collider_queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = m.collider_queries_terms[2..].ptr, .term_count = 1 }, .{ .terms = m.collider_queries_terms[3..].ptr, .term_count = 1 } };

    var cp = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    cp.name = "physics.collider2d";
    cp.phase = abi_runtime.KE_PHASE_FIXED_POST_UPDATE;
    cp.queries = &m.collider_queries;
    cp.query_count = m.collider_queries.len;
    cp.pinned_thread = 0;
    cp.user_data = m;
    cp.execute = colliderSystem;
    m.collider_system = 0;
    try R.check(rt.*.register_system.?(rt, &cp, &m.collider_system));

    return .{ .ref = @ptrCast(m), .destroy = destroyHandle };
}

const Components = @import("scene_components").Set(&.{
    .{ .name = abi_physics.KE_COMPONENT_NAME_BODY2D, .size = @sizeOf(abi_physics.ke_body2d_component), .alignment = @alignOf(abi_physics.ke_body2d_component), .fields = &abi_physics.ke_body2d_component_fields },
    .{ .name = abi_physics.KE_COMPONENT_NAME_COLLIDER2D, .size = @sizeOf(abi_physics.ke_collider2d_component), .alignment = @alignOf(abi_physics.ke_collider2d_component), .fields = &abi_physics.ke_collider2d_component_fields },
});

/// The factory of the scene component set. The set holds no state, so it cannot fail.
export fn ke_physics_scene_components_create() callconv(.c) abi_framework.ke_scene_component_set_handle {
    return Components.handle();
}

const testing = std.testing;

fn made(params: ?*const abi_physics_body2d_factory.ke_physics_body2d_module_params) !abi_physics_body2d_factory.ke_physics_body2d_module_handle {
    var h: abi_physics_body2d_factory.ke_physics_body2d_module_handle = undefined;
    try R.check(ke_physics_body2d_module_create(params, &h));
    return h;
}

const Stubs = @import("stubs");

test "creating and destroying the body2d module leaves no block allocated and no system registered" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var physics = std.mem.zeroes(abi_physics.ke_physics_2d);

    var params = std.mem.zeroes(abi_physics_body2d_factory.ke_physics_body2d_module_params);
    params.runtime = rt.api();
    params.ecs = ecs.api();
    params.physics = &physics;
    var tree: Stubs.Tree = undefined;
    tree.init();
    params.scene_tree = tree.api();

    const h = try made(&params);
    try testing.expectEqual(@as(u32, 2), rt.registered);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(u32, 0), rt.live_count);
    try heap.expectNoLeaks();
}

test "a body2d module missing its runtime, ecs, physics or scene tree is refused" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var physics = std.mem.zeroes(abi_physics.ke_physics_2d);

    var params = std.mem.zeroes(abi_physics_body2d_factory.ke_physics_body2d_module_params);
    try testing.expect(std.meta.isError(made(null)));
    try testing.expect(std.meta.isError(made(&params)));
    params.runtime = rt.api();
    try testing.expect(std.meta.isError(made(&params)));
    params.ecs = ecs.api();
    try testing.expect(std.meta.isError(made(&params)));
    params.physics = &physics;
    try testing.expect(std.meta.isError(made(&params)));
    var tree: Stubs.Tree = undefined;
    tree.init();
    params.scene_tree = tree.api();
    const h = try made(&params);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

test "a body2d module the runtime refuses a system of fails the create and leaves no system registered" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var physics = std.mem.zeroes(abi_physics.ke_physics_2d);

    for ([_]u32{ 0, 1 }) |limit| {
        var rt: Stubs.Runtime = undefined;
        rt.init();
        rt.limit = limit;
        var params = std.mem.zeroes(abi_physics_body2d_factory.ke_physics_body2d_module_params);
        params.runtime = rt.api();
        params.ecs = ecs.api();
        params.physics = &physics;
        var tree: Stubs.Tree = undefined;
        tree.init();
        params.scene_tree = tree.api();

        try testing.expect(std.meta.isError(made(&params)));
        try testing.expectEqual(@as(u32, 0), rt.live_count);
        try heap.expectNoLeaks();
    }
}

const FakeWorld = struct {
    var next_body: abi_physics.ke_body_2d = 1;
    var destroyed: [4]abi_physics.ke_body_2d = undefined;
    var destroyed_count: usize = 0;

    fn reset() void {
        next_body = 1;
        destroyed_count = 0;
    }

    fn createBody(_: [*c]abi_physics.ke_physics_2d, _: abi_physics.ke_body_type_2d, _: f32, _: f32, out_body: [*c]abi_physics.ke_body_2d) callconv(.c) abi_result.ke_result {
        next_body += 1;
        out_body.* = next_body - 1;
        return R.ok;
    }

    fn destroyBody(_: [*c]abi_physics.ke_physics_2d, body: abi_physics.ke_body_2d) callconv(.c) void {
        destroyed[destroyed_count] = body;
        destroyed_count += 1;
    }

    fn getBodyState(_: [*c]abi_physics.ke_physics_2d, _: abi_physics.ke_body_2d, out: [*c]abi_physics.ke_body_state_2d) callconv(.c) void {
        out.* = std.mem.zeroes(abi_physics.ke_body_state_2d);
    }

    fn setBodyPosition(_: [*c]abi_physics.ke_physics_2d, _: abi_physics.ke_body_2d, _: f32, _: f32, _: f32) callconv(.c) void {}
    fn setBodyVelocity(_: [*c]abi_physics.ke_physics_2d, _: abi_physics.ke_body_2d, _: f32, _: f32) callconv(.c) void {}
    fn setBodyFixedRotation(_: [*c]abi_physics.ke_physics_2d, _: abi_physics.ke_body_2d, _: bool) callconv(.c) void {}
    fn setBodyGravityScale(_: [*c]abi_physics.ke_physics_2d, _: abi_physics.ke_body_2d, _: f32) callconv(.c) void {}
    fn step(_: [*c]abi_physics.ke_physics_2d, _: f32) callconv(.c) void {}

    fn api() abi_physics.ke_physics_2d {
        var p = std.mem.zeroes(abi_physics.ke_physics_2d);
        p.create_body = createBody;
        p.destroy_body = destroyBody;
        p.get_body_state = getBodyState;
        p.set_body_position = setBodyPosition;
        p.set_body_velocity = setBodyVelocity;
        p.set_body_fixed_rotation = setBodyFixedRotation;
        p.set_body_gravity_scale = setBodyGravityScale;
        p.step = step;
        return p;
    }
};

const BodyView = struct {
    var bodies: [1]abi_physics.ke_body2d_component = undefined;
    var transforms: [1]abi_spatial.ke_transform2d_component = undefined;
    var entities: [1]abi_ecs.ke_entity = .{7};
    var columns: [2]?*anyopaque = undefined;
    var segment: abi_ecs.ke_ecs_segment = undefined;
    var live: usize = 1;

    fn view(_: [*c]abi_runtime.ke_system_ctx, _: u32, out_count: [*c]usize) callconv(.c) [*c]const abi_ecs.ke_ecs_segment {
        segment = std.mem.zeroes(abi_ecs.ke_ecs_segment);
        segment.count = live;
        segment.entities = &entities;
        columns = .{ &bodies, &transforms };
        segment.columns = columns[0..].ptr;
        segment.column_count = 2;
        out_count.* = 1;
        return &segment;
    }
};

test "a body whose entity no longer holds it is destroyed on the next update" {
    FakeWorld.reset();
    var physics = FakeWorld.api();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    const m = try gpa.create(Module);
    var tree: Stubs.Tree = undefined;
    tree.init();
    m.* = .{ .physics = &physics, .runtime = rt.api(), .tree = tree.api() };
    var ctx = std.mem.zeroes(abi_runtime.ke_system_ctx);
    ctx.view = BodyView.view;

    BodyView.bodies[0] = std.mem.zeroes(abi_physics.ke_body2d_component);
    BodyView.transforms[0] = std.mem.zeroes(abi_spatial.ke_transform2d_component);
    BodyView.live = 1;
    try testing.expect(bodySystem(&ctx, m, 0.0) == R.ok);
    try testing.expect(bodySystem(&ctx, m, 0.0) == R.ok);
    const body = BodyView.bodies[0].body;
    try testing.expect(body != abi_physics.KE_BODY_2D_INVALID);
    try testing.expectEqual(@as(usize, 0), FakeWorld.destroyed_count);

    BodyView.live = 0;
    try testing.expect(bodySystem(&ctx, m, 0.0) == R.ok);
    try testing.expectEqual(@as(usize, 1), FakeWorld.destroyed_count);
    try testing.expectEqual(body, FakeWorld.destroyed[0]);

    destroyHandle(@ptrCast(m));
    try testing.expectEqual(@as(usize, 1), FakeWorld.destroyed_count);
    try heap.expectNoLeaks();
}

const OrphanView = struct {
    var colliders: [1]abi_physics.ke_collider2d_component = undefined;
    var transforms: [1]abi_spatial.ke_transform2d_component = undefined;
    var hierarchies: [1]abi_framework.ke_hierarchy_component = undefined;
    var entities: [1]abi_ecs.ke_entity = .{9};
    var columns: [2]?*anyopaque = undefined;
    var segment: abi_ecs.ke_ecs_segment = undefined;
    var hierarchy_reads: usize = 0;

    fn view(_: [*c]abi_runtime.ke_system_ctx, index: u32, out_count: [*c]usize) callconv(.c) [*c]const abi_ecs.ke_ecs_segment {
        segment = std.mem.zeroes(abi_ecs.ke_ecs_segment);
        segment.entities = &entities;
        segment.count = 1;
        switch (index) {
            0 => columns = .{ &colliders, &transforms },
            2 => {
                hierarchy_reads += 1;
                columns = .{ &hierarchies, null };
            },
            else => segment.count = 0,
        }
        segment.columns = columns[0..].ptr;
        out_count.* = 1;
        return &segment;
    }
};

test "a collider with no body above it is retried only once the hierarchy has moved" {
    var physics = FakeWorld.api();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var tree: Stubs.Tree = undefined;
    tree.init();
    const m = try gpa.create(Module);
    m.* = .{ .physics = &physics, .runtime = rt.api(), .tree = tree.api() };
    var ctx = std.mem.zeroes(abi_runtime.ke_system_ctx);
    ctx.view = OrphanView.view;

    OrphanView.colliders[0] = std.mem.zeroes(abi_physics.ke_collider2d_component);
    OrphanView.hierarchies[0] = std.mem.zeroes(abi_framework.ke_hierarchy_component);
    OrphanView.hierarchy_reads = 0;

    try testing.expect(colliderSystem(&ctx, m, 0.0) == R.ok);
    try testing.expect(colliderSystem(&ctx, m, 0.0) == R.ok);
    try testing.expectEqual(@as(usize, 1), OrphanView.hierarchy_reads);

    tree.generation += 1;
    try testing.expect(colliderSystem(&ctx, m, 0.0) == R.ok);
    try testing.expectEqual(@as(usize, 2), OrphanView.hierarchy_reads);
    try testing.expect(!OrphanView.colliders[0].attached);

    destroyHandle(@ptrCast(m));
    try heap.expectNoLeaks();
}

test "destroying the module destroys the bodies it created" {
    FakeWorld.reset();
    var physics = FakeWorld.api();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    const m = try gpa.create(Module);
    var tree: Stubs.Tree = undefined;
    tree.init();
    m.* = .{ .physics = &physics, .runtime = rt.api(), .tree = tree.api() };
    var ctx = std.mem.zeroes(abi_runtime.ke_system_ctx);
    ctx.view = BodyView.view;

    BodyView.bodies[0] = std.mem.zeroes(abi_physics.ke_body2d_component);
    BodyView.live = 1;
    try testing.expect(bodySystem(&ctx, m, 0.0) == R.ok);

    destroyHandle(@ptrCast(m));
    try testing.expectEqual(@as(usize, 1), FakeWorld.destroyed_count);
    try heap.expectNoLeaks();
}

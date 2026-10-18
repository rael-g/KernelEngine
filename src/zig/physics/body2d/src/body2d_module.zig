//! Keeps the entity components of 2D bodies and colliders in agreement with a `ke_physics_2d`
//! world, through two update-phase systems. It also exports the set of those components a scene
//! file can author.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("c");

const heap = @import("heap");
var gpa = heap.gpa;

/// A body the module created, and the update in which its entity was last seen holding it.
const Tracked = struct {
    body: c.ke_body_2d,
    seen: u64,
};

/// The state behind the handle `ke_physics_body2d_module_create` returns, owned by that handle.
/// The query declarations point into this struct's own term arrays, so its address must stay
/// fixed while the two systems are registered. `physics` and `logger` are borrowed from the
/// params; `logger` may be null. `tracked` holds every body the module created, by entity, and
/// `update` counts the body system's runs, so a body whose entity no longer holds it is found.
const Module = struct {
    physics: *c.ke_physics_2d,
    runtime: *c.ke_runtime,
    tree: *c.ke_scene_tree,
    body_generation: u64 = 0,
    attempt: ?Attempt = null,
    body_system: c.ke_system_id = 0,
    collider_system: c.ke_system_id = 0,
    logger: ?*c.ke_logger = null,
    tracked: std.AutoHashMapUnmanaged(c.ke_entity, Tracked) = .empty,
    update: u64 = 0,
    body_queries_terms: [2]c.ke_component_access = undefined,
    body_queries: [1]c.ke_query_decl = undefined,
    collider_queries_terms: [4]c.ke_component_access = undefined,
    collider_queries: [3]c.ke_query_decl = undefined,
};

/// What the collider system last tried to attach against: the tree's hierarchy generation, the
/// module's body generation and the number of colliders. An unattached collider is retried only
/// once one of them differs.
const Attempt = struct { hierarchy: u64, bodies: u64, colliders: usize };

fn moduleOf(user: ?*anyopaque) *Module {
    return @ptrCast(@alignCast(user.?));
}

fn log(logger: ?*c.ke_logger, level: c_int, comptime fmt: []const u8, args: anytype) void {
    const lg = logger orelse return;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch return;
    var ev = c.ke_log_event{ .level = level, .tag = "physics.body2d", .message = msg.ptr };
    if (lg.log) |f| f(lg, &ev);
}

/// The update-phase system that reconciles every body with its component and transform, in this
/// order: a component with no body gets one at its transform's position and rotation; a transform
/// or a velocity that differs from the world's pushes it in; the world steps by `dt`; every body's
/// state is then written back, its velocities into its component and its position and angle into
/// its transform. A body created here is therefore simulated in the same update. The body type,
/// gravity scale and fixed rotation are read only when the body is created. A failed creation, or
/// a body the module cannot record, leaves the component without a body, to be retried on the next
/// update; nothing is written to the error output and the system still returns true. Before the
/// step, a recorded body whose entity no longer holds it, destroyed or stripped of the component,
/// is destroyed.
fn bodySystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const m = moduleOf(user);
    const p = m.physics;
    m.update += 1;

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);

    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const bodies: [*c]c.ke_body2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const tcs0: [*c]c.ke_transform2d_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            const b = &bodies[i];
            const pose = tcs0[i];
            if (b.body == c.KE_BODY_2D_INVALID) {
                b.body = p.create_body.?(p, b.type, pose.position.x, pose.position.y, null);
                if (b.body == c.KE_BODY_2D_INVALID) continue;
                m.tracked.put(gpa, segs[s].entities[i], .{ .body = b.body, .seen = m.update }) catch {
                    p.destroy_body.?(p, b.body);
                    b.body = c.KE_BODY_2D_INVALID;
                    continue;
                };
                m.body_generation +%= 1;
                p.set_body_position.?(p, b.body, pose.position.x, pose.position.y, pose.rotation);
                p.set_body_velocity.?(p, b.body, b.velocity.x, b.velocity.y);
                p.set_body_fixed_rotation.?(p, b.body, b.fixed_rotation);
                p.set_body_gravity_scale.?(p, b.body, b.gravity_scale);
                log(m.logger, c.KE_LOG_LEVEL_INFO,
                    "body on entity {d}: type={d} pos=({d:.3},{d:.3}) angle={d:.4} scale=({d:.3},{d:.3})",
                    .{ segs[s].entities[i], b.type, pose.position.x, pose.position.y, pose.rotation, pose.scale.x, pose.scale.y });
                continue;
            }

            if (m.tracked.getPtr(segs[s].entities[i])) |t| t.seen = m.update;

            var st: c.ke_body_state_2d = undefined;
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
        const bodies: [*c]c.ke_body2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const tcs: [*c]c.ke_transform2d_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            const b = &bodies[i];
            if (b.body == c.KE_BODY_2D_INVALID) continue;

            var st: c.ke_body_state_2d = undefined;
            p.get_body_state.?(p, b.body, &st);

            b.velocity = .{ .x = st.velocity_x, .y = st.velocity_y };
            b.angular_velocity = st.angular_velocity;

            tcs[i].position = .{ .x = st.x, .y = st.y };
            tcs[i].rotation = st.angle;
        }
    }
    return true;
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
fn countColliders(ctx: ?*c.ke_system_ctx) struct { total: usize, unattached: usize } {
    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    var total: usize = 0;
    var unattached: usize = 0;
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const cols: [*c]c.ke_collider2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        total += segs[s].count;
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            if (!cols[i].attached) unattached += 1;
        }
    }
    return .{ .total = total, .unattached = unattached };
}

/// The update-phase system that attaches fixtures to colliders. It returns at once when every
/// collider is attached, or when neither the tree's hierarchy generation, the module's body
/// generation nor the number of colliders moved since its last attempt, so a collider that
/// resolved to no body is retried, and its warning logged again, only once its ancestors or the
/// bodies may have changed. Otherwise each unattached collider is resolved to a body through
/// `findBody` and gets a fixture whose offset is its own transform's position. Its entity indexes
/// are complete before the first fixture is added, so an out-of-memory failure, reported through
/// the error output, leaves every collider unattached. A shape that resolves to no body, or whose
/// fixture the world refuses, is logged and stays unattached; neither is reported through the
/// error output.
fn colliderSystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    _ = dt;
    const m = moduleOf(user);
    const p = m.physics;

    const counted = countColliders(ctx);
    if (counted.unattached == 0) return true;
    const attempt: Attempt = .{ .hierarchy = m.tree.hierarchy_generation.?(m.tree), .bodies = m.body_generation, .colliders = counted.total };
    if (m.attempt) |last| if (std.meta.eql(last, attempt)) return true;

    var parents = std.AutoHashMap(c.ke_entity, c.ke_entity).init(gpa);
    defer parents.deinit();
    var bodies = std.AutoHashMap(c.ke_entity, c.ke_body_2d).init(gpa);
    defer bodies.deinit();

    var segc: usize = 0;
    var segs = ctx.?.view.?(ctx, 2, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const hs: [*c]c.ke_hierarchy_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            parents.put(segs[s].entities[i], hs[i].parent) catch {
                c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "collider pass: parent index allocation failed", @src().file, @intCast(@src().line), null);
                return false;
            };
        }
    }

    segs = ctx.?.view.?(ctx, 1, &segc);
    s = 0;
    while (s < segc) : (s += 1) {
        const bs: [*c]c.ke_body2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            if (bs[i].body == c.KE_BODY_2D_INVALID) continue;
            bodies.put(segs[s].entities[i], bs[i].body) catch {
                c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "collider pass: body index allocation failed", @src().file, @intCast(@src().line), null);
                return false;
            };
        }
    }

    segs = ctx.?.view.?(ctx, 0, &segc);
    s = 0;
    while (s < segc) : (s += 1) {
        const cols: [*c]c.ke_collider2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const tcs: [*c]c.ke_transform2d_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            const col = &cols[i];
            if (col.attached) continue;

            const body = findBody(&parents, &bodies, segs[s].entities[i]) orelse {
                log(m.logger, c.KE_LOG_LEVEL_WARNING,
                    "shape on entity {d} resolves to no body; it will never collide", .{segs[s].entities[i]});
                continue;
            };

            const off = tcs[i].position;
            const angle = tcs[i].rotation;
            const filter = c.ke_collision_filter_2d{ .layer = col.layer, .mask = col.mask };
            const ok = switch (col.kind) {
                c.KE_SHAPE_KIND_2D_CIRCLE => p.add_circle_fixture.?(p, body, col.radius, off.x, off.y, col.density, col.friction, col.restitution, &filter, null),
                else => p.add_box_fixture.?(p, body, col.half_extents.x, col.half_extents.y, off.x, off.y, angle, col.density, col.friction, col.restitution, &filter, null),
            };
            col.attached = ok;
            log(m.logger, if (ok) c.KE_LOG_LEVEL_INFO else c.KE_LOG_LEVEL_ERROR,
                "shape on entity {d}: kind={d} half=({d:.3},{d:.3}) r={d:.3} off=({d:.3},{d:.3}) angle={d:.4} density={d:.3} friction={d:.3} restitution={d:.3} attached={}",
                .{ segs[s].entities[i], col.kind, col.half_extents.x, col.half_extents.y, col.radius, off.x, off.y, angle, col.density, col.friction, col.restitution, ok });
        }
    }
    m.attempt = attempt;
    return true;
}

/// Walks the parent links above `start`, the shape's own entity, and returns the first body found
/// on that chain, or null when the chain ends first. The shape's own entity is not checked, only
/// its ancestors. The steps are bounded by the size of the parent index, so a cycle ends the walk.
fn findBody(
    parents: *std.AutoHashMap(c.ke_entity, c.ke_entity),
    bodies: *std.AutoHashMap(c.ke_entity, c.ke_body_2d),
    start: c.ke_entity,
) ?c.ke_body_2d {
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
fn destroyHandle(self: ?*c.ke_physics_body2d_module) callconv(.c) void {
    const m: *Module = @ptrCast(@alignCast(self orelse return));
    _ = m.runtime.unregister_system.?(m.runtime, m.collider_system, null);
    _ = m.runtime.unregister_system.?(m.runtime, m.body_system, null);
    var it = m.tracked.valueIterator();
    while (it.next()) |t| m.physics.destroy_body.?(m.physics, t.body);
    m.tracked.deinit(gpa);
    gpa.destroy(m);
}

/// Registers the component ids with the ECS, then the body system and the collider system, both in
/// the update phase. A missing argument or a failed allocation returns a null handle and sets
/// nothing on the error output. A system the runtime refuses passes the runtime's error through
/// the error output and returns a null handle. On success, the handle's `destroy` frees the module.
export fn ke_physics_body2d_module_create(
    params: ?*const c.ke_physics_body2d_module_params,
    out_error: ?*?*c.ke_error,
) callconv(.c) c.ke_physics_body2d_module_handle {
    const empty: c.ke_physics_body2d_module_handle = .{ .ref = null, .destroy = null };

    const pr = params orelse return empty;
    const rt = pr.runtime orelse return empty;
    const ecs = pr.ecs orelse return empty;
    const physics = pr.physics orelse return empty;
    const tree = pr.scene_tree orelse return empty;

    const m = gpa.create(Module) catch return empty;
    m.* = .{ .physics = physics, .runtime = rt, .tree = tree, .logger = pr.logger };

    const body_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_BODY2D, @sizeOf(c.ke_body2d_component), &c.ke_body2d_component_fields, c.ke_body2d_component_fields.len, null);
    const transform_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_TRANSFORM2D, @sizeOf(c.ke_transform2d_component), &c.ke_transform2d_component_fields, c.ke_transform2d_component_fields.len, null);
    const collider_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_COLLIDER2D, @sizeOf(c.ke_collider2d_component), &c.ke_collider2d_component_fields, c.ke_collider2d_component_fields.len, null);
    const hierarchy_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_HIERARCHY, @sizeOf(c.ke_hierarchy_component), null, 0, null);

    const rd = c.KE_ACCESS_READ;
    const wr = c.KE_ACCESS_WRITE;
    m.body_queries_terms = .{ .{ .cid = body_cid, .access = wr }, .{ .cid = transform_cid, .access = wr } };
    m.body_queries = .{ .{ .terms = &m.body_queries_terms[0], .term_count = 2 } };

    var sp = std.mem.zeroes(c.ke_runtime_system_params);
    sp.name = "physics.body2d";
    sp.phase = c.KE_PHASE_UPDATE;
    sp.queries = &m.body_queries;
    sp.query_count = m.body_queries.len;
    sp.pinned_thread = 0;
    sp.user_data = m;
    sp.execute = bodySystem;
    m.body_system = rt.*.register_system.?(rt, &sp, @ptrCast(out_error));
    if (m.body_system == 0) {
        gpa.destroy(m);
        return empty;
    }
    m.collider_queries_terms = .{ .{ .cid = collider_cid, .access = wr }, .{ .cid = transform_cid, .access = rd }, .{ .cid = body_cid, .access = rd }, .{ .cid = hierarchy_cid, .access = rd } };
    m.collider_queries = .{ .{ .terms = &m.collider_queries_terms[0], .term_count = 2 }, .{ .terms = &m.collider_queries_terms[2], .term_count = 1 }, .{ .terms = &m.collider_queries_terms[3], .term_count = 1 } };

    var cp = std.mem.zeroes(c.ke_runtime_system_params);
    cp.name = "physics.collider2d";
    cp.phase = c.KE_PHASE_UPDATE;
    cp.queries = &m.collider_queries;
    cp.query_count = m.collider_queries.len;
    cp.pinned_thread = 0;
    cp.user_data = m;
    cp.execute = colliderSystem;
    m.collider_system = rt.*.register_system.?(rt, &cp, @ptrCast(out_error));
    if (m.collider_system == 0) {
        _ = rt.*.unregister_system.?(rt, m.body_system, null);
        gpa.destroy(m);
        return empty;
    }

    return .{ .ref = @ptrCast(m), .destroy = destroyHandle };
}

const Components = @import("scene_components").Set(c, &.{
    .{ .name = c.KE_COMPONENT_NAME_BODY2D, .size = @sizeOf(c.ke_body2d_component), .fields = &c.ke_body2d_component_fields },
    .{ .name = c.KE_COMPONENT_NAME_COLLIDER2D, .size = @sizeOf(c.ke_collider2d_component), .fields = &c.ke_collider2d_component_fields },
});

/// The factory of the scene component set. The set holds no state, so it cannot fail.
export fn ke_physics_scene_components_create() callconv(.c) c.ke_scene_component_set_handle {
    return Components.handle();
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the body2d module leaves no block allocated and no system registered" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var physics = std.mem.zeroes(c.ke_physics_2d);

    var params = std.mem.zeroes(c.ke_physics_body2d_module_params);
    params.runtime = rt.api();
    params.ecs = ecs.api();
    params.physics = &physics;
    var tree: Stubs.Tree = undefined;
    tree.init();
    params.scene_tree = tree.api();

    const h = ke_physics_body2d_module_create(&params, null);
    try testing.expect(h.ref != null);
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
    var physics = std.mem.zeroes(c.ke_physics_2d);

    var params = std.mem.zeroes(c.ke_physics_body2d_module_params);
    try testing.expect(ke_physics_body2d_module_create(null, null).ref == null);
    try testing.expect(ke_physics_body2d_module_create(&params, null).ref == null);
    params.runtime = rt.api();
    try testing.expect(ke_physics_body2d_module_create(&params, null).ref == null);
    params.ecs = ecs.api();
    try testing.expect(ke_physics_body2d_module_create(&params, null).ref == null);
    params.physics = &physics;
    try testing.expect(ke_physics_body2d_module_create(&params, null).ref == null);
    var tree: Stubs.Tree = undefined;
    tree.init();
    params.scene_tree = tree.api();
    const h = ke_physics_body2d_module_create(&params, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

test "a body2d module the runtime refuses a system of fails the create and leaves no system registered" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var physics = std.mem.zeroes(c.ke_physics_2d);

    for ([_]u32{ 0, 1 }) |limit| {
        var rt: Stubs.Runtime = undefined;
        rt.init();
        rt.limit = limit;
        var params = std.mem.zeroes(c.ke_physics_body2d_module_params);
        params.runtime = rt.api();
        params.ecs = ecs.api();
        params.physics = &physics;
        var tree: Stubs.Tree = undefined;
        tree.init();
        params.scene_tree = tree.api();

        try testing.expect(ke_physics_body2d_module_create(&params, null).ref == null);
        try testing.expectEqual(@as(u32, 0), rt.live_count);
        try heap.expectNoLeaks();
    }
}

const FakeWorld = struct {
    var next_body: c.ke_body_2d = 1;
    var destroyed: [4]c.ke_body_2d = undefined;
    var destroyed_count: usize = 0;

    fn reset() void {
        next_body = 1;
        destroyed_count = 0;
    }

    fn createBody(_: [*c]c.ke_physics_2d, _: c.ke_body_type_2d, _: f32, _: f32, _: [*c][*c]c.ke_error) callconv(.c) c.ke_body_2d {
        next_body += 1;
        return next_body - 1;
    }

    fn destroyBody(_: [*c]c.ke_physics_2d, body: c.ke_body_2d) callconv(.c) void {
        destroyed[destroyed_count] = body;
        destroyed_count += 1;
    }

    fn getBodyState(_: [*c]c.ke_physics_2d, _: c.ke_body_2d, out: [*c]c.ke_body_state_2d) callconv(.c) void {
        out.* = std.mem.zeroes(c.ke_body_state_2d);
    }

    fn setBodyPosition(_: [*c]c.ke_physics_2d, _: c.ke_body_2d, _: f32, _: f32, _: f32) callconv(.c) void {}
    fn setBodyVelocity(_: [*c]c.ke_physics_2d, _: c.ke_body_2d, _: f32, _: f32) callconv(.c) void {}
    fn setBodyFixedRotation(_: [*c]c.ke_physics_2d, _: c.ke_body_2d, _: bool) callconv(.c) void {}
    fn setBodyGravityScale(_: [*c]c.ke_physics_2d, _: c.ke_body_2d, _: f32) callconv(.c) void {}
    fn step(_: [*c]c.ke_physics_2d, _: f32) callconv(.c) void {}

    fn api() c.ke_physics_2d {
        var p = std.mem.zeroes(c.ke_physics_2d);
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
    var bodies: [1]c.ke_body2d_component = undefined;
    var transforms: [1]c.ke_transform2d_component = undefined;
    var entities: [1]c.ke_entity = .{7};
    var columns: [2]?*anyopaque = undefined;
    var segment: c.ke_ecs_segment = undefined;
    var live: usize = 1;

    fn view(_: [*c]c.ke_system_ctx, _: u32, out_count: [*c]usize) callconv(.c) [*c]const c.ke_ecs_segment {
        segment = std.mem.zeroes(c.ke_ecs_segment);
        segment.count = live;
        segment.entities = &entities;
        columns = .{ &bodies, &transforms };
        segment.columns = &columns[0];
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
    var ctx = std.mem.zeroes(c.ke_system_ctx);
    ctx.view = BodyView.view;

    BodyView.bodies[0] = std.mem.zeroes(c.ke_body2d_component);
    BodyView.transforms[0] = std.mem.zeroes(c.ke_transform2d_component);
    BodyView.live = 1;
    try testing.expect(bodySystem(&ctx, m, 0.0, null));
    try testing.expect(bodySystem(&ctx, m, 0.0, null));
    const body = BodyView.bodies[0].body;
    try testing.expect(body != c.KE_BODY_2D_INVALID);
    try testing.expectEqual(@as(usize, 0), FakeWorld.destroyed_count);

    BodyView.live = 0;
    try testing.expect(bodySystem(&ctx, m, 0.0, null));
    try testing.expectEqual(@as(usize, 1), FakeWorld.destroyed_count);
    try testing.expectEqual(body, FakeWorld.destroyed[0]);

    destroyHandle(@ptrCast(m));
    try testing.expectEqual(@as(usize, 1), FakeWorld.destroyed_count);
    try heap.expectNoLeaks();
}

const OrphanView = struct {
    var colliders: [1]c.ke_collider2d_component = undefined;
    var transforms: [1]c.ke_transform2d_component = undefined;
    var hierarchies: [1]c.ke_hierarchy_component = undefined;
    var entities: [1]c.ke_entity = .{9};
    var columns: [2]?*anyopaque = undefined;
    var segment: c.ke_ecs_segment = undefined;
    var hierarchy_reads: usize = 0;

    fn view(_: [*c]c.ke_system_ctx, index: u32, out_count: [*c]usize) callconv(.c) [*c]const c.ke_ecs_segment {
        segment = std.mem.zeroes(c.ke_ecs_segment);
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
        segment.columns = &columns[0];
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
    var ctx = std.mem.zeroes(c.ke_system_ctx);
    ctx.view = OrphanView.view;

    OrphanView.colliders[0] = std.mem.zeroes(c.ke_collider2d_component);
    OrphanView.hierarchies[0] = std.mem.zeroes(c.ke_hierarchy_component);
    OrphanView.hierarchy_reads = 0;

    try testing.expect(colliderSystem(&ctx, m, 0.0, null));
    try testing.expect(colliderSystem(&ctx, m, 0.0, null));
    try testing.expectEqual(@as(usize, 1), OrphanView.hierarchy_reads);

    tree.generation += 1;
    try testing.expect(colliderSystem(&ctx, m, 0.0, null));
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
    var ctx = std.mem.zeroes(c.ke_system_ctx);
    ctx.view = BodyView.view;

    BodyView.bodies[0] = std.mem.zeroes(c.ke_body2d_component);
    BodyView.live = 1;
    try testing.expect(bodySystem(&ctx, m, 0.0, null));

    destroyHandle(@ptrCast(m));
    try testing.expectEqual(@as(usize, 1), FakeWorld.destroyed_count);
    try heap.expectNoLeaks();
}

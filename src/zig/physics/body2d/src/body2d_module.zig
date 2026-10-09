//! Binds the 2D physics world to the entity component store: the component that describes a body
//! is the authority over it until the world steps, and the world is the authority after.
//!
//! Creating the module registers the component ids it needs and two update-phase systems, both
//! pinned to the same worker, with a `Module` that holds their query declarations and borrows the
//! physics handle. The world owns the bodies; the module only holds their ids in components.
//!
//! `bodySystem` is the loop. Components that have no body get one, components whose stored state
//! differs from the world's push it in, the world steps, and every body's state is written back
//! into its component and its transform. A body is therefore simulated in the update that created
//! it. `colliderSystem` is the second system: it does nothing until `anyUnattached` finds a
//! collider without a fixture, then resolves each such collider to a body, its own ancestors
//! being searched through `findBody`, and adds the fixture. A collider that fails to resolve or
//! attach stays unattached and is tried again on later updates.
//!
//! Failure is soft inside the systems and strict at creation: a failed body or fixture is
//! retried, not reported, while the create function returns a null handle when an argument is
//! missing, memory runs out or the runtime refuses a system, leaving no system registered.
//! `ke_physics_register_scene_apply` is the separate export that makes scene blocks for the body
//! and collider components applicable.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("cimport.zig").c;

const heap = @import("heap");
var gpa = heap.gpa;

/// The state behind the handle `ke_physics_body2d_module_create` returns, owned by that handle.
/// The query declarations point into this struct's own term arrays, so its address must stay
/// fixed while the two systems are registered. `physics` and `logger` are borrowed from the
/// params; `logger` may be null.
const Module = struct {
    physics: *c.ke_physics_2d,
    logger: ?*c.ke_logger = null,
    body_queries_terms: [2]c.ke_component_access = undefined,
    body_queries: [1]c.ke_query_decl = undefined,
    collider_queries_terms: [4]c.ke_component_access = undefined,
    collider_queries: [3]c.ke_query_decl = undefined,
};

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

/// The update-phase system that reconciles every body with its component. It runs before the world
/// step, so a body created here is simulated in the same update. A component whose stored position
/// is exactly zero first takes the transform's position and rotation. A failed creation leaves the
/// component without a body, to be retried on the next update; nothing is written to the error
/// output and the system still returns true.
fn bodySystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const m = moduleOf(user);
    const p = m.physics;

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);

    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const bodies: [*c]c.ke_body2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const tcs0: [*c]c.ke_transform2d_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            const b = &bodies[i];
            if (b.body == c.KE_BODY_2D_INVALID) {
                if (b.position.x == 0 and b.position.y == 0) {
                    b.position = tcs0[i].position;
                    b.angle = tcs0[i].rotation;
                }
                b.body = p.create_body.?(p, b.type, b.position.x, b.position.y, null);
                if (b.body == c.KE_BODY_2D_INVALID) continue;
                p.set_body_velocity.?(p, b.body, b.velocity.x, b.velocity.y);
                p.set_body_fixed_rotation.?(p, b.body, b.fixed_rotation);
                p.set_body_gravity_scale.?(p, b.body, b.gravity_scale);
                log(m.logger, c.KE_LOG_LEVEL_INFO,
                    "body on entity {d}: type={d} pos=({d:.3},{d:.3}) angle={d:.4} scale=({d:.3},{d:.3})",
                    .{ segs[s].entities[i], b.type, b.position.x, b.position.y, b.angle, tcs0[i].scale.x, tcs0[i].scale.y });
                continue;
            }

            var st: c.ke_body_state_2d = undefined;
            p.get_body_state.?(p, b.body, &st);
            if (b.position.x != st.x or b.position.y != st.y or b.angle != st.angle)
                p.set_body_position.?(p, b.body, b.position.x, b.position.y, b.angle);
            if (b.velocity.x != st.velocity_x or b.velocity.y != st.velocity_y)
                p.set_body_velocity.?(p, b.body, b.velocity.x, b.velocity.y);
        }
    }

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

            b.position = .{ .x = st.x, .y = st.y };
            b.angle = st.angle;
            b.velocity = .{ .x = st.velocity_x, .y = st.velocity_y };
            b.angular_velocity = st.angular_velocity;

            tcs[i].position = .{ .x = st.x, .y = st.y };
            tcs[i].rotation = st.angle;
        }
    }
    return true;
}

/// Lets `colliderSystem` return before it builds any index when every collider already has its
/// fixture.
fn anyUnattached(ctx: ?*c.ke_system_ctx) bool {
    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const cols: [*c]c.ke_collider2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) if (!cols[i].attached) return true;
    }
    return false;
}

/// The update-phase system that attaches fixtures to colliders. Its entity indexes are complete
/// before the first fixture is added, so an out-of-memory failure, reported through the error
/// output, leaves every collider unattached. A shape that resolves to no body, or whose fixture the
/// world refuses, is logged and stays unattached; neither is reported through the error output.
fn colliderSystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    _ = dt;
    const m = moduleOf(user);
    const p = m.physics;

    if (!anyUnattached(ctx)) return true;

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
/// of that handle.
fn destroyHandle(self: ?*c.ke_physics_body2d_module) callconv(.c) void {
    const m: *Module = @ptrCast(@alignCast(self orelse return));
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

    const m = gpa.create(Module) catch return empty;
    m.* = .{ .physics = physics, .logger = pr.logger };

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
    const body_system = rt.*.register_system.?(rt, &sp, @ptrCast(out_error));
    if (body_system == 0) {
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
    if (rt.*.register_system.?(rt, &cp, @ptrCast(out_error)) == 0) {
        _ = rt.*.unregister_system.?(rt, body_system, null);
        gpa.destroy(m);
        return empty;
    }

    return .{ .ref = @ptrCast(m), .destroy = destroyHandle };
}

fn registerFields(w: *c.ke_world, cid: c.ke_component_id, table: anytype) void {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    _ = w.register_component_fields.?(w, cid, table, @intCast(fields.len), null);
}

/// Registers the body and collider component ids with `ecs`, then their field tables with `world`,
/// so scene blocks for those components apply to it. Returns false when either pointer is null.
/// The result of each field-table registration is discarded, so true does not confirm that the
/// tables were accepted.
export fn ke_physics_register_scene_apply(ecs: ?*c.ke_ecs, world: ?*c.ke_world) callconv(.c) bool {
    const e = ecs orelse return false;
    const w = world orelse return false;

    const body_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_BODY2D, @sizeOf(c.ke_body2d_component), &c.ke_body2d_component_fields, c.ke_body2d_component_fields.len, null);
    const collider_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_COLLIDER2D, @sizeOf(c.ke_collider2d_component), &c.ke_collider2d_component_fields, c.ke_collider2d_component_fields.len, null);

    registerFields(w, body_cid, &c.ke_body2d_component_fields);
    registerFields(w, collider_cid, &c.ke_collider2d_component_fields);
    return true;
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the body2d module leaves no block allocated and registers its two systems" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var physics = std.mem.zeroes(c.ke_physics_2d);

    var params = std.mem.zeroes(c.ke_physics_body2d_module_params);
    params.runtime = rt.api();
    params.ecs = ecs.api();
    params.physics = &physics;

    const h = ke_physics_body2d_module_create(&params, null);
    try testing.expect(h.ref != null);
    try testing.expectEqual(@as(u32, 2), rt.registered);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

test "a body2d module missing its runtime, ecs or physics is refused" {
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

        try testing.expect(ke_physics_body2d_module_create(&params, null).ref == null);
        try testing.expectEqual(@as(u32, 0), rt.live_count);
        try heap.expectNoLeaks();
    }
}

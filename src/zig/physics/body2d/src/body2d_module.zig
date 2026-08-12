const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("cimport.zig").c;

var gpa = std.heap.c_allocator;

const Module = struct {
    physics: *c.ke_physics_2d,
    body_queries: [1]c.ke_query_decl = undefined,
    collider_queries: [3]c.ke_query_decl = undefined,
};

fn moduleOf(user: ?*anyopaque) *Module {
    return @ptrCast(@alignCast(user.?));
}

/// A quaternion carrying only a Z-axis rotation, which is the whole of a 2D
/// body's orientation once expressed in the 3D transform every node composes.
fn zRotation(angle: f32) c.ke_quat {
    const half = angle * 0.5;
    return .{ .x = 0, .y = 0, .z = @sin(half), .w = @cos(half) };
}

fn bodySystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) void {
    const m = moduleOf(user);
    const p = m.physics;

    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &segc);

    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const bodies: [*c]c.ke_body2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            const b = &bodies[i];
            if (b.body != c.KE_BODY_2D_INVALID) continue;

            b.body = p.create_body.?(p, b.type, b.position.x, b.position.y, null);
            if (b.body == c.KE_BODY_2D_INVALID) continue;
            p.set_body_velocity.?(p, b.body, b.velocity.x, b.velocity.y);
            p.set_body_fixed_rotation.?(p, b.body, b.fixed_rotation);
            p.set_body_gravity_scale.?(p, b.body, b.gravity_scale);
        }
    }

    p.step.?(p, dt);

    s = 0;
    while (s < segc) : (s += 1) {
        const bodies: [*c]c.ke_body2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const tcs: [*c]c.ke_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
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

            tcs[i].position.x = st.x;
            tcs[i].position.y = st.y;
            tcs[i].rotation = zRotation(st.angle);
        }
    }
}

fn anyUnattached(ctx: ?*c.ke_system_ctx) bool {
    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const cols: [*c]c.ke_collider2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) if (!cols[i].attached) return true;
    }
    return false;
}

fn colliderSystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) void {
    _ = dt;
    const m = moduleOf(user);
    const p = m.physics;

    if (!anyUnattached(ctx)) return;

    var parents = std.AutoHashMap(c.ke_entity, c.ke_entity).init(gpa);
    defer parents.deinit();
    var bodies = std.AutoHashMap(c.ke_entity, c.ke_body_2d).init(gpa);
    defer bodies.deinit();

    var segc: usize = 0;
    var segs = c.ke_system_ctx_view(ctx, 2, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const hs: [*c]c.ke_hierarchy_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            parents.put(segs[s].entities[i], hs[i].parent) catch return;
        }
    }

    segs = c.ke_system_ctx_view(ctx, 1, &segc);
    s = 0;
    while (s < segc) : (s += 1) {
        const bs: [*c]c.ke_body2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            if (bs[i].body == c.KE_BODY_2D_INVALID) continue;
            bodies.put(segs[s].entities[i], bs[i].body) catch return;
        }
    }

    segs = c.ke_system_ctx_view(ctx, 0, &segc);
    s = 0;
    while (s < segc) : (s += 1) {
        const cols: [*c]c.ke_collider2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            const col = &cols[i];
            if (col.attached) continue;

            const body = findBody(&parents, &bodies, segs[s].entities[i]) orelse continue;

            const ok = switch (col.kind) {
                c.KE_SHAPE_KIND_2D_CIRCLE => p.add_circle_fixture.?(p, body, col.radius, col.density, col.friction, col.restitution, null),
                else => p.add_box_fixture.?(p, body, col.half_extents.x, col.half_extents.y, col.density, col.friction, col.restitution, null),
            };
            col.attached = ok;
        }
    }
}

/// Climbs the hierarchy from a shape to the nearest entity that owns a body.
/// Bounded by the parent map's size so a hierarchy corrupted into a cycle
/// terminates rather than hanging the tick.
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

fn destroyHandle(self: ?*c.ke_physics_body2d_module) callconv(.c) void {
    const m: *Module = @ptrCast(@alignCast(self orelse return));
    gpa.destroy(m);
}

export fn ke_physics_body2d_module_create(
    params: ?*const c.ke_physics_body2d_module_params,
    out_error: ?*?*c.ke_error,
) callconv(.c) c.ke_physics_body2d_module_handle {
    _ = out_error;
    const empty: c.ke_physics_body2d_module_handle = .{ .ref = null, .destroy = null };

    const pr = params orelse return empty;
    const rt = pr.runtime orelse return empty;
    const ecs = pr.ecs orelse return empty;
    const physics = pr.physics orelse return empty;

    const m = gpa.create(Module) catch return empty;
    m.* = .{ .physics = physics };

    const body_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_BODY_2D, @sizeOf(c.ke_body2d_component), null);
    const transform_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component), null);
    const collider_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_COLLIDER_2D, @sizeOf(c.ke_collider2d_component), null);
    const hierarchy_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_HIERARCHY, @sizeOf(c.ke_hierarchy_component), null);

    const rd = c.KE_ACCESS_READ;
    const wr = c.KE_ACCESS_WRITE;

    m.body_queries = std.mem.zeroes([1]c.ke_query_decl);
    m.body_queries[0].terms[0] = .{ .cid = body_cid, .access = wr };
    m.body_queries[0].terms[1] = .{ .cid = transform_cid, .access = wr };
    m.body_queries[0].term_count = 2;

    var sp = std.mem.zeroes(c.ke_runtime_system_params);
    sp.name = "physics.body2d";
    sp.phase = c.KE_PHASE_UPDATE;
    sp.queries = &m.body_queries;
    sp.query_count = m.body_queries.len;
    sp.pinned_thread = 0;
    sp.user_data = m;
    sp.execute = bodySystem;
    _ = rt.*.register_system.?(rt, &sp, null);

    m.collider_queries = std.mem.zeroes([3]c.ke_query_decl);
    m.collider_queries[0].terms[0] = .{ .cid = collider_cid, .access = wr };
    m.collider_queries[0].term_count = 1;
    m.collider_queries[1].terms[0] = .{ .cid = body_cid, .access = rd };
    m.collider_queries[1].term_count = 1;
    m.collider_queries[2].terms[0] = .{ .cid = hierarchy_cid, .access = rd };
    m.collider_queries[2].term_count = 1;

    var cp = std.mem.zeroes(c.ke_runtime_system_params);
    cp.name = "physics.collider2d";
    cp.phase = c.KE_PHASE_UPDATE;
    cp.queries = &m.collider_queries;
    cp.query_count = m.collider_queries.len;
    cp.pinned_thread = 0;
    cp.user_data = m;
    cp.execute = colliderSystem;
    _ = rt.*.register_system.?(rt, &cp, null);

    return .{ .ref = @ptrCast(m), .destroy = destroyHandle };
}

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("cimport.zig").c;

var gpa = std.heap.c_allocator;

const Module = struct {
    physics: *c.ke_physics_2d,
    logger: ?*c.ke_logger = null,
    body_queries: [1]c.ke_query_decl = undefined,
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

fn bodySystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) void {
    const m = moduleOf(user);
    const p = m.physics;

    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &segc);

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
            const ok = switch (col.kind) {
                c.KE_SHAPE_KIND_2D_CIRCLE => p.add_circle_fixture.?(p, body, col.radius, off.x, off.y, col.density, col.friction, col.restitution, null),
                else => p.add_box_fixture.?(p, body, col.half_extents.x, col.half_extents.y, off.x, off.y, angle, col.density, col.friction, col.restitution, null),
            };
            col.attached = ok;
            log(m.logger, if (ok) c.KE_LOG_LEVEL_INFO else c.KE_LOG_LEVEL_ERROR,
                "shape on entity {d}: kind={d} half=({d:.3},{d:.3}) r={d:.3} off=({d:.3},{d:.3}) angle={d:.4} density={d:.3} friction={d:.3} restitution={d:.3} attached={}",
                .{ segs[s].entities[i], col.kind, col.half_extents.x, col.half_extents.y, col.radius, off.x, off.y, angle, col.density, col.friction, col.restitution, ok });
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
    m.* = .{ .physics = physics, .logger = pr.logger };

    const body_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_BODY_2D, @sizeOf(c.ke_body2d_component), null);
    const transform_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_TRANSFORM_2D, @sizeOf(c.ke_transform2d_component), null);
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
    m.collider_queries[0].terms[1] = .{ .cid = transform_cid, .access = rd };
    m.collider_queries[0].term_count = 2;
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

/// Registers a generated field table, taking its length from the array type so
/// the count can never drift from the table it describes.
fn registerFields(w: *c.ke_world, cid: c.ke_component_id, table: anytype) void {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    _ = w.register_component_fields.?(w, cid, table, @intCast(fields.len), null);
}

export fn ke_physics_register_scene_apply(ecs: ?*c.ke_ecs, world: ?*c.ke_world) callconv(.c) bool {
    const e = ecs orelse return false;
    const w = world orelse return false;

    const body_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_BODY_2D, @sizeOf(c.ke_body2d_component), null);
    const collider_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_COLLIDER_2D, @sizeOf(c.ke_collider2d_component), null);

    registerFields(w, body_cid, &c.ke_body2d_component_fields);
    registerFields(w, collider_cid, &c.ke_collider2d_component_fields);
    return true;
}

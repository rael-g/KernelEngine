// The system that makes ke_body2d_component mean something: it creates the body
// an entity describes, advances the world once per tick, and writes the result
// back into the component and the transform it composes.
//
// It never sees a physics backend. Everything goes through the ke_physics_2d
// vtable, so the reconciliation is written once regardless of which plugin
// implements the world.

const std = @import("std");

// This .so is dlopen'd by a foreign, non-Zig host alongside many sibling
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack exceeds glibc's small static-TLS surplus once enough plugins
// accumulate, aborting with "cannot allocate memory in static TLS block".
pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("cimport.zig").c;

var gpa = std.heap.c_allocator;

const Module = struct {
    physics: *c.ke_physics_2d,
    queries: [1]c.ke_query_decl = undefined,
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

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) void {
    const m = moduleOf(user);
    const p = m.physics;

    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &segc);

    // Creation happens before the step so a body authored this tick is simulated
    // this tick, rather than sitting inert for one frame.
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
        }
    }

    p.step.?(p, dt);

    // The simulation is authoritative for pose and motion from here on, so the
    // component is written FROM the body, and the transform from the component —
    // one direction, no reconciliation of two writers for the same value.
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

            // Z is left alone: it is the caller's draw-order depth, which the 2D
            // simulation has no opinion about and must not overwrite.
            tcs[i].position.x = st.x;
            tcs[i].position.y = st.y;
            tcs[i].rotation = zRotation(st.angle);
        }
    }
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

    const body_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_BODY_2D,
        @sizeOf(c.ke_body2d_component), null);
    const transform_cid = ecs.*.component_register.?(ecs, c.KE_COMPONENT_NAME_TRANSFORM,
        @sizeOf(c.ke_transform_component), null);

    // Both terms are writes: the body's own fields are simulation output, and the
    // transform is derived from them. Declaring the transform read-only would let
    // the wave-builder run this alongside another writer of the same component.
    const wr = c.KE_ACCESS_WRITE;
    m.queries = std.mem.zeroes([1]c.ke_query_decl);
    m.queries[0].terms[0] = .{ .cid = body_cid, .access = wr };
    m.queries[0].terms[1] = .{ .cid = transform_cid, .access = wr };
    m.queries[0].term_count = 2;

    var sp = std.mem.zeroes(c.ke_runtime_system_params);
    sp.name = "physics.body2d";
    sp.phase = c.KE_PHASE_UPDATE;
    sp.queries = &m.queries;
    sp.query_count = m.queries.len;
    sp.pinned_thread = 0;
    sp.user_data = m;
    sp.execute = system;
    _ = rt.*.register_system.?(rt, &sp, null);

    return .{ .ref = @ptrCast(m), .destroy = destroyHandle };
}

// ke_physics_2d backed by Box2D v3.
//
// Box2D v3 addresses bodies by value handle (b2BodyId: index + world +
// generation) rather than by pointer, so the id table maps the engine's opaque
// ke_body_2d onto that struct instead of onto a pointer. Everything else keeps
// the behaviour the previous implementation settled on — see the notes at each
// decision point.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

/// Box2D v3 replaced v2's separate velocity/position iteration counts with a
/// single sub-step count; 4 is the value its own docs call usual.
const sub_step_count: c_int = 4;

const initial_body_capacity: u32 = 64;

/// ke_body_2d is a dense index into `bodies`, biased by one so that 0 stays the
/// invalid sentinel the contract reserves.
const Entry = struct {
    body: c.b2BodyId,
    live: bool,
};

const State = struct {
    api: c.ke_physics_2d,
    logger: ?*c.ke_logger, // borrowed; may be null
    world: c.b2WorldId,
    bodies: ?[*]Entry,
    body_count: u32,
    body_capacity: u32,
};

fn stateOf(self: *c.ke_physics_2d) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn logInfo(logger: ?*c.ke_logger, msg: [*:0]const u8) void {
    const lg = logger orelse return;
    var ev = c.ke_log_event{
        .level = c.KE_LOG_LEVEL_INFO,
        .tag = "box2d",
        .message = msg,
    };
    if (lg.log) |f| f(lg, &ev);
}

/// Returns the body for a handle, or null when the handle is the invalid
/// sentinel, out of range, or refers to a slot already destroyed.
fn lookup(s: *State, id: c.ke_body_2d) ?c.b2BodyId {
    if (id == c.KE_BODY_2D_INVALID) return null;
    const idx = id - 1;
    if (idx >= s.body_count) return null;
    const entry = s.bodies.?[idx];
    return if (entry.live) entry.body else null;
}

// -- vtable ------------------------------------------------------------------

fn setGravity(self_in: ?*c.ke_physics_2d, x: f32, y: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    c.b2World_SetGravity(stateOf(self).world, .{ .x = x, .y = y });
}

fn step(self_in: ?*c.ke_physics_2d, dt: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    c.b2World_Step(stateOf(self).world, dt, sub_step_count);
}

fn createBody(
    self_in: ?*c.ke_physics_2d,
    body_type: c.ke_body_type_2d,
    x: f32,
    y: f32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_body_2d {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_BODY_2D_INVALID;
    };
    if (self.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_BODY_2D_INVALID;
    }
    const s = stateOf(self);

    if (s.body_count == s.body_capacity) {
        const cap = if (s.body_capacity != 0) s.body_capacity * 2 else initial_body_capacity;
        const buf = heap.gpa.alloc(Entry, cap) catch {
            E.fail(out_error, .out_of_memory, "body table allocation failed", @src());
            return c.KE_BODY_2D_INVALID;
        };
        if (s.bodies) |old| {
            @memcpy(buf[0..s.body_count], old[0..s.body_count]);
            heap.gpa.free(old[0..s.body_capacity]);
        }
        s.bodies = buf.ptr;
        s.body_capacity = cap;
    }

    var def = c.b2DefaultBodyDef();
    def.type = switch (body_type) {
        c.KE_BODY_TYPE_STATIC => c.b2_staticBody,
        c.KE_BODY_TYPE_KINEMATIC => c.b2_kinematicBody,
        else => c.b2_dynamicBody,
    };
    def.position = .{ .x = x, .y = y };

    const body = c.b2CreateBody(s.world, &def);
    if (!c.b2Body_IsValid(body)) {
        E.fail(out_error, .out_of_memory, "body creation failed", @src());
        return c.KE_BODY_2D_INVALID;
    }

    s.bodies.?[s.body_count] = .{ .body = body, .live = true };
    s.body_count += 1;
    // Bias by one: handle 0 is reserved as invalid.
    return @intCast(s.body_count);
}

fn destroyBody(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    const body = lookup(s, id) orelse return;
    c.b2DestroyBody(body);
    // The slot is retired rather than reused: handles already handed out must
    // not silently start addressing a different body.
    s.bodies.?[id - 1].live = false;
}

/// Shared by the box and circle paths: v3 carries friction and restitution on
/// the shape's surface material, with density left on the def itself.
fn makeShapeDef(density: f32, friction: f32, restitution: f32) c.b2ShapeDef {
    var def = c.b2DefaultShapeDef();
    def.density = density;
    def.material.friction = friction;
    def.material.restitution = restitution;
    return def;
}

fn addBoxFixture(
    self_in: ?*c.ke_physics_2d,
    id: c.ke_body_2d,
    half_w: f32,
    half_h: f32,
    density: f32,
    friction: f32,
    restitution: f32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const body = lookup(stateOf(self), id) orelse {
        E.fail(out_error, .not_found, "body not found", @src());
        return false;
    };

    const def = makeShapeDef(density, friction, restitution);
    const box = c.b2MakeBox(half_w, half_h);
    _ = c.b2CreatePolygonShape(body, &def, &box);
    return true;
}

fn addCircleFixture(
    self_in: ?*c.ke_physics_2d,
    id: c.ke_body_2d,
    radius: f32,
    density: f32,
    friction: f32,
    restitution: f32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const body = lookup(stateOf(self), id) orelse {
        E.fail(out_error, .not_found, "body not found", @src());
        return false;
    };

    const def = makeShapeDef(density, friction, restitution);
    // Centered on the body origin, matching the contract.
    const circle = c.b2Circle{ .center = .{ .x = 0, .y = 0 }, .radius = radius };
    _ = c.b2CreateCircleShape(body, &def, &circle);
    return true;
}

fn getBodyState(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d, out_in: ?*c.ke_body_state_2d) callconv(.c) void {
    const out = out_in orelse return;
    // Zeroed up front so an unknown handle reads as a resting body at the
    // origin rather than as uninitialised memory.
    out.* = std.mem.zeroes(c.ke_body_state_2d);

    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;

    const p = c.b2Body_GetPosition(body);
    const v = c.b2Body_GetLinearVelocity(body);
    out.x = p.x;
    out.y = p.y;
    // v3 stores orientation as a cosine/sine pair; the contract wants radians.
    out.angle = rotAngle(c.b2Body_GetRotation(body));
    out.velocity_x = v.x;
    out.velocity_y = v.y;
    out.angular_velocity = c.b2Body_GetAngularVelocity(body);
}

fn setBodyPosition(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d, x: f32, y: f32, angle: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    c.b2Body_SetTransform(body, .{ .x = x, .y = y }, makeRot(angle));
}

fn setBodyVelocity(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d, vx: f32, vy: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    c.b2Body_SetLinearVelocity(body, .{ .x = vx, .y = vy });
}

fn applyImpulse(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d, ix: f32, iy: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    // wake = true: an impulse aimed at a sleeping body is meant to move it.
    c.b2Body_ApplyLinearImpulseToCenter(body, .{ .x = ix, .y = iy }, true);
}

fn setBodyFixedRotation(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d, fixed: bool) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    c.b2Body_SetFixedRotation(body, fixed);
}

// -- rotation helpers --------------------------------------------------------
//
// b2MakeRot / b2Rot_GetAngle are static inline in Box2D's headers, so they
// export no symbol to link against and translate-c does not always lower them.
// Reimplemented here against the same representation (a unit cosine/sine pair).

fn makeRot(radians: f32) c.b2Rot {
    return .{ .c = @cos(radians), .s = @sin(radians) };
}

fn rotAngle(q: c.b2Rot) f32 {
    return std.math.atan2(q.s, q.c);
}

// -- teardown ----------------------------------------------------------------

fn destroy(self_in: ?*c.ke_physics_2d) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    // Destroying the world takes every body with it, so the table only needs
    // its own storage released.
    c.b2DestroyWorld(s.world);
    if (s.bodies) |b| heap.gpa.free(b[0..s.body_capacity]);
    heap.gpa.destroy(s);
}

// -- factory -----------------------------------------------------------------

export fn ke_physics_2d_box2d_create(
    params_in: ?*const c.ke_physics_2d_box2d_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_physics_2d_handle {
    const null_handle = std.mem.zeroes(c.ke_physics_2d_handle);

    const params = params_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null_handle;
    };

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = .{
        .api = std.mem.zeroes(c.ke_physics_2d),
        .logger = params.logger,
        .world = undefined,
        .bodies = null,
        .body_count = 0,
        .body_capacity = 0,
    };

    var world_def = c.b2DefaultWorldDef();
    // The caller's gravity is used verbatim — zero means zero, which top-down
    // games rely on. The managed AddBox2D() supplies (0, -9.81) as its default,
    // so omitting it still yields Earth gravity.
    world_def.gravity = .{ .x = params.gravity_x, .y = params.gravity_y };
    s.world = c.b2CreateWorld(&world_def);
    if (!c.b2World_IsValid(s.world)) {
        heap.gpa.destroy(s);
        E.fail(out_error, .general, "physics world creation failed", @src());
        return null_handle;
    }

    s.api.handle = s;
    s.api.set_gravity = setGravity;
    s.api.step = step;
    s.api.create_body = createBody;
    s.api.destroy_body = destroyBody;
    s.api.add_box_fixture = addBoxFixture;
    s.api.add_circle_fixture = addCircleFixture;
    s.api.get_body_state = getBodyState;
    s.api.set_body_position = setBodyPosition;
    s.api.set_body_velocity = setBodyVelocity;
    s.api.apply_impulse = applyImpulse;
    s.api.set_body_fixed_rotation = setBodyFixedRotation;

    logInfo(s.logger, "Box2D physics world initialized");
    return .{ .ref = &s.api, .destroy = destroy };
}

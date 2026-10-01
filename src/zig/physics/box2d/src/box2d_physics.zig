const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const c = @import("c.zig").c;
const heap = @import("heap");

const E = @import("kerror").Errors(c);

const sub_step_count: c_int = 4;

const initial_body_capacity: u32 = 64;

const Entry = struct {
    body: c.b2BodyId,
    live: bool,
};

const State = struct {
    api: c.ke_physics_2d,
    logger: ?*c.ke_logger,
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

fn lookup(s: *State, id: c.ke_body_2d) ?c.b2BodyId {
    if (id == c.KE_BODY_2D_INVALID) return null;
    const idx = id - 1;
    if (idx >= s.body_count) return null;
    const entry = s.bodies.?[idx];
    return if (entry.live) entry.body else null;
}

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
    return @intCast(s.body_count);
}

fn destroyBody(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    const body = lookup(s, id) orelse return;
    c.b2DestroyBody(body);
    s.bodies.?[id - 1].live = false;
}

fn makeShapeDef(
    density: f32,
    friction: f32,
    restitution: f32,
    filter: ?*const c.ke_collision_filter_2d,
) c.b2ShapeDef {
    var def = c.b2DefaultShapeDef();
    def.density = density;
    def.material.friction = friction;
    def.material.restitution = restitution;
    if (filter) |f| {
        def.filter.categoryBits = f.layer;
        def.filter.maskBits = f.mask;
    }
    return def;
}

fn addBoxFixture(
    self_in: ?*c.ke_physics_2d,
    id: c.ke_body_2d,
    half_w: f32,
    half_h: f32,
    offset_x: f32,
    offset_y: f32,
    offset_angle: f32,
    density: f32,
    friction: f32,
    restitution: f32,
    filter: ?*const c.ke_collision_filter_2d,
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

    const def = makeShapeDef(density, friction, restitution, filter);
    const box = c.b2MakeOffsetBox(half_w, half_h, .{ .x = offset_x, .y = offset_y }, makeRot(offset_angle));
    _ = c.b2CreatePolygonShape(body, &def, &box);
    return true;
}

fn addCircleFixture(
    self_in: ?*c.ke_physics_2d,
    id: c.ke_body_2d,
    radius: f32,
    offset_x: f32,
    offset_y: f32,
    density: f32,
    friction: f32,
    restitution: f32,
    filter: ?*const c.ke_collision_filter_2d,
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

    const def = makeShapeDef(density, friction, restitution, filter);
    const circle = c.b2Circle{ .center = .{ .x = offset_x, .y = offset_y }, .radius = radius };
    _ = c.b2CreateCircleShape(body, &def, &circle);
    return true;
}

fn getBodyState(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d, out_in: ?*c.ke_body_state_2d) callconv(.c) void {
    const out = out_in orelse return;
    out.* = std.mem.zeroes(c.ke_body_state_2d);

    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;

    const p = c.b2Body_GetPosition(body);
    const v = c.b2Body_GetLinearVelocity(body);
    out.x = p.x;
    out.y = p.y;
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
    c.b2Body_ApplyLinearImpulseToCenter(body, .{ .x = ix, .y = iy }, true);
}

fn setBodyFixedRotation(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d, fixed: bool) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    c.b2Body_SetFixedRotation(body, fixed);
}

fn setBodyGravityScale(self_in: ?*c.ke_physics_2d, id: c.ke_body_2d, scale: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    c.b2Body_SetGravityScale(body, scale);
}

fn makeRot(radians: f32) c.b2Rot {
    return .{ .c = @cos(radians), .s = @sin(radians) };
}

fn rotAngle(q: c.b2Rot) f32 {
    return std.math.atan2(q.s, q.c);
}

fn destroy(self_in: ?*c.ke_physics_2d) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    c.b2DestroyWorld(s.world);
    if (s.bodies) |b| heap.gpa.free(b[0..s.body_capacity]);
    heap.gpa.destroy(s);
    heap.release();
}

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
    s.api.set_body_gravity_scale = setBodyGravityScale;

    logInfo(s.logger, "Box2D physics world initialized");
    heap.retain();
    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;

fn makeWorld(gravity_x: f32, gravity_y: f32) c.ke_physics_2d_handle {
    var params = std.mem.zeroes(c.ke_physics_2d_box2d_params);
    params.logger = null;
    params.gravity_x = gravity_x;
    params.gravity_y = gravity_y;
    return ke_physics_2d_box2d_create(&params, null);
}

test "creating a world yields a usable vtable" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref != null);
    try testing.expect(h.destroy != null);
}

test "setting gravity on a fresh world is accepted" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    h.ref.*.set_gravity.?(h.ref, 0.0, -10.0);
}

test "stepping an empty world is accepted" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    h.ref.*.step.?(h.ref, 0.016);
}

test "creating a body returns a handle that is not the invalid sentinel" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    try testing.expect(body != c.KE_BODY_2D_INVALID);
}

test "a box fixture attaches to an existing body" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    try testing.expect(h.ref.*.add_box_fixture.?(h.ref, body, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.3, 0.1, null, null));
}

test "a circle fixture attaches to an existing body" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    try testing.expect(h.ref.*.add_circle_fixture.?(h.ref, body, 1.0, 0.0, 0.0, 1.0, 0.3, 0.1, null, null));
}

test "a body reports the position it was created at" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 10.0, 20.0, null);

    var state = std.mem.zeroes(c.ke_body_state_2d);
    h.ref.*.get_body_state.?(h.ref, body, &state);

    try testing.expectApproxEqAbs(@as(f32, 10.0), state.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 20.0), state.y, 1e-5);
}

test "setting a body position moves it and sets its angle" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    h.ref.*.set_body_position.?(h.ref, body, 5.0, 5.0, 0.78);

    var state = std.mem.zeroes(c.ke_body_state_2d);
    h.ref.*.get_body_state.?(h.ref, body, &state);

    try testing.expectApproxEqAbs(@as(f32, 5.0), state.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 5.0), state.y, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.78), state.angle, 1e-5);
}

test "setting a body velocity is readable back before any step" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    h.ref.*.set_body_velocity.?(h.ref, body, 1.0, 2.0);

    var state = std.mem.zeroes(c.ke_body_state_2d);
    h.ref.*.get_body_state.?(h.ref, body, &state);

    try testing.expectApproxEqAbs(@as(f32, 1.0), state.velocity_x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 2.0), state.velocity_y, 1e-5);
}

test "an impulse pushes a body along both axes it was applied on" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    try testing.expect(h.ref.*.add_box_fixture.?(h.ref, body, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.3, 0.1, null, null));
    h.ref.*.apply_impulse.?(h.ref, body, 10.0, 10.0);

    h.ref.*.step.?(h.ref, 0.016);

    var state = std.mem.zeroes(c.ke_body_state_2d);
    h.ref.*.get_body_state.?(h.ref, body, &state);

    try testing.expect(state.velocity_x > 0.0);
    try testing.expect(state.velocity_y > 0.0);
}

test "destroying a body retires its handle" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    h.ref.*.destroy_body.?(h.ref, body);

    var state = c.ke_body_state_2d{
        .x = 42.0,
        .y = 42.0,
        .angle = 42.0,
        .velocity_x = 42.0,
        .velocity_y = 42.0,
        .angular_velocity = 42.0,
    };
    h.ref.*.get_body_state.?(h.ref, body, &state);

    try testing.expectApproxEqAbs(@as(f32, 0.0), state.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.0), state.y, 1e-5);
}

test "a rotation locked box never picks up spin when it bounces off a wall" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_STATIC, 2.0, 0.0, null);
    try testing.expect(wall != c.KE_BODY_2D_INVALID);
    try testing.expect(h.ref.*.add_box_fixture.?(h.ref, wall, 0.25, 4.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, null, null));

    const ball = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    try testing.expect(ball != c.KE_BODY_2D_INVALID);
    try testing.expect(h.ref.*.add_box_fixture.?(h.ref, ball, 0.18, 0.18, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, null, null));
    h.ref.*.set_body_fixed_rotation.?(h.ref, ball, true);
    h.ref.*.set_body_velocity.?(h.ref, ball, 6.0, 0.0);

    var state = std.mem.zeroes(c.ke_body_state_2d);
    var i: usize = 0;
    while (i < 120) : (i += 1) {
        h.ref.*.step.?(h.ref, 1.0 / 60.0);
        h.ref.*.get_body_state.?(h.ref, ball, &state);
        try testing.expectApproxEqAbs(@as(f32, 0.0), state.angular_velocity, 1e-5);
    }

    try testing.expectApproxEqAbs(@as(f32, 0.0), state.angle, 1e-5);
    try testing.expect(state.velocity_x < 0.0);
}

test "a frictionless circle hitting a wall head on does not start spinning" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_STATIC, 2.0, 0.0, null);
    try testing.expect(h.ref.*.add_box_fixture.?(h.ref, wall, 0.25, 4.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, null, null));

    const ball = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    try testing.expect(h.ref.*.add_circle_fixture.?(h.ref, ball, 0.18, 0.0, 0.0, 1.0, 0.0, 1.0, null, null));
    h.ref.*.set_body_velocity.?(h.ref, ball, 6.0, 0.0);

    var state = std.mem.zeroes(c.ke_body_state_2d);
    var i: usize = 0;
    while (i < 120) : (i += 1) {
        h.ref.*.step.?(h.ref, 1.0 / 60.0);
        h.ref.*.get_body_state.?(h.ref, ball, &state);
        try testing.expectApproxEqAbs(@as(f32, 0.0), state.angular_velocity, 1e-3);
    }
}

fn wallAndBall(h: c.ke_physics_2d_handle, wall_filter: ?*const c.ke_collision_filter_2d, ball_filter: ?*const c.ke_collision_filter_2d) c.ke_body_2d {
    const wall = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_STATIC, 2.0, 0.0, null);
    _ = h.ref.*.add_box_fixture.?(h.ref, wall, 0.25, 4.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, wall_filter, null);

    const ball = h.ref.*.create_body.?(h.ref, c.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0, null);
    _ = h.ref.*.add_box_fixture.?(h.ref, ball, 0.18, 0.18, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, ball_filter, null);
    h.ref.*.set_body_velocity.?(h.ref, ball, 6.0, 0.0);
    return ball;
}

fn runPast(h: c.ke_physics_2d_handle, ball: c.ke_body_2d) c.ke_body_state_2d {
    var state = std.mem.zeroes(c.ke_body_state_2d);
    var i: usize = 0;
    while (i < 120) : (i += 1) {
        h.ref.*.step.?(h.ref, 1.0 / 60.0);
    }
    h.ref.*.get_body_state.?(h.ref, ball, &state);
    return state;
}

test "a shape whose mask excludes the other's layer passes straight through it" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall_filter = c.ke_collision_filter_2d{ .layer = 0b10, .mask = 0b10 };
    const ball_filter = c.ke_collision_filter_2d{ .layer = 0b01, .mask = 0b01 };
    const ball = wallAndBall(h, &wall_filter, &ball_filter);

    const state = runPast(h, ball);
    try testing.expect(state.velocity_x > 0.0);
    try testing.expect(state.x > 2.0);
}

test "the same pair collides once each mask names the other's layer" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall_filter = c.ke_collision_filter_2d{ .layer = 0b10, .mask = 0b11 };
    const ball_filter = c.ke_collision_filter_2d{ .layer = 0b01, .mask = 0b11 };
    const ball = wallAndBall(h, &wall_filter, &ball_filter);

    const state = runPast(h, ball);
    try testing.expect(state.velocity_x < 0.0);
}

test "clearing one side of the pair is enough to silence the contact" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall_filter = c.ke_collision_filter_2d{ .layer = 0b10, .mask = 0b11 };
    const ball_filter = c.ke_collision_filter_2d{ .layer = 0b01, .mask = 0b01 };
    const ball = wallAndBall(h, &wall_filter, &ball_filter);

    const state = runPast(h, ball);
    try testing.expect(state.x > 2.0);
}

test "a null filter leaves the fixture colliding with everything" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const ball = wallAndBall(h, null, null);
    const state = runPast(h, ball);
    try testing.expect(state.velocity_x < 0.0);
}

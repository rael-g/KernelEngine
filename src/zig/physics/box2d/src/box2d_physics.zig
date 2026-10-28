//! The Box2D backend of the 2D physics contract: the exported factory `ke_physics_2d_box2d_create`
//! and the slots of the `ke_physics_2d` it returns, all working on one world.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_physics_2d_box2d").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const abi_physics = @import("abi_physics");
const abi_result = @import("abi_result");
const abi_factory = @import("abi_physics_2d_box2d_factory");
const b2 = @import("box2d");
const heap = @import("heap");

/// Error reporter bound to this file's C error types; every failure in this file is reported
/// through it.
const R = @import("result").Result(.{});

const sub_step_count: c_int = 4;

const initial_body_capacity: u32 = 64;

/// One position of the body table. Once `live` is false the Box2D body has been destroyed and
/// `body` is no longer valid. The entry stays in the table so its position is not reused.
const Entry = struct {
    body: b2.b2BodyId,
    live: bool,
};

/// Allocated by the factory and freed by `destroy`. `bodies` is null until the first body is
/// created, and then holds `body_capacity` entries, of which the first `body_count` are used.
/// `world` is assigned before the factory returns the state's vtable. A body id handed through
/// the contract is its position in `bodies` plus one, so zero stays `KE_BODY_2D_INVALID`; a
/// destroyed body keeps its position, marked dead, so an id is never reused and a stale id fails
/// `lookup`. Fixtures are not tracked here: they belong to the Box2D body. Nothing locks, so a
/// world must be driven from one thread at a time.
const State = struct {
    api: abi_physics.ke_physics_2d,
    world: b2.b2WorldId,
    bodies: ?[*]Entry,
    body_count: u32,
    body_capacity: u32,
};

fn stateOf(self: *abi_physics.ke_physics_2d) *State {
    return @ptrCast(@alignCast(self.handle));
}

const log = std.log.scoped(.physics_2d_box2d);

/// Every operation on an existing body resolves its id here. A null result means the operation
/// does nothing or reports that the body was not found.
fn lookup(s: *State, id: abi_physics.ke_body_2d) ?b2.b2BodyId {
    if (id == abi_physics.KE_BODY_2D_INVALID) return null;
    const idx = id - 1;
    if (idx >= s.body_count) return null;
    const entry = s.bodies.?[idx];
    return if (entry.live) entry.body else null;
}

/// Takes effect on the next step; a null vtable or handle is ignored.
fn setGravity(self_in: ?*abi_physics.ke_physics_2d, x: f32, y: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    b2.b2World_SetGravity(stateOf(self).world, .{ .x = x, .y = y });
}

/// Advances the world by the given seconds, split into `sub_step_count` sub-steps. It does not
/// read the body table.
fn step(self_in: ?*abi_physics.ke_physics_2d, dt: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    b2.b2World_Step(stateOf(self).world, dt, sub_step_count);
}

/// Grows the body table before the body is created, so a failed table allocation leaves nothing
/// created. If Box2D refuses the body, the grown table is kept and the count does not change. On
/// success the id written is the new count. Fails with invalid argument for a null vtable, handle
/// or out-parameter and out of memory for a failed table growth or a refused body.
fn createBody(
    self_in: ?*abi_physics.ke_physics_2d,
    body_type: abi_physics.ke_body_type_2d,
    x: f32,
    y: f32,
    out_body: ?*abi_physics.ke_body_2d,
) callconv(.c) abi_result.ke_result {
    const out = out_body orelse return R.code(error.InvalidArgument);
    out.* = abi_physics.KE_BODY_2D_INVALID;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);

    if (s.body_count == s.body_capacity) {
        const cap = if (s.body_capacity != 0) s.body_capacity * 2 else initial_body_capacity;
        const buf = heap.gpa.alloc(Entry, cap) catch return R.code(error.OutOfMemory);
        if (s.bodies) |old| {
            @memcpy(buf[0..s.body_count], old[0..s.body_count]);
            heap.gpa.free(old[0..s.body_capacity]);
        }
        s.bodies = buf.ptr;
        s.body_capacity = cap;
    }

    var def = b2.b2DefaultBodyDef();
    def.type = switch (body_type) {
        abi_physics.KE_BODY_TYPE_STATIC => b2.b2_staticBody,
        abi_physics.KE_BODY_TYPE_KINEMATIC => b2.b2_kinematicBody,
        else => b2.b2_dynamicBody,
    };
    def.position = .{ .x = x, .y = y };

    const body = b2.b2CreateBody(s.world, &def);
    if (!b2.b2Body_IsValid(body)) {
        log.warn("Box2D refused a body", .{});
        return R.code(error.OutOfMemory);
    }

    s.bodies.?[s.body_count] = .{ .body = body, .live = true };
    s.body_count += 1;
    out.* = @intCast(s.body_count);
    return R.ok;
}

/// Destroys the Box2D body together with its fixtures and marks its entry dead; an id that does
/// not resolve does nothing.
fn destroyBody(self_in: ?*abi_physics.ke_physics_2d, id: abi_physics.ke_body_2d) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    const body = lookup(s, id) orelse return;
    b2.b2DestroyBody(body);
    s.bodies.?[id - 1].live = false;
}

/// A null filter leaves Box2D's default filter, which collides with everything; otherwise the
/// filter's layer and mask become the shape's category and mask bits.
fn makeShapeDef(
    density: f32,
    friction: f32,
    restitution: f32,
    filter: ?*const abi_physics.ke_collision_filter_2d,
) b2.b2ShapeDef {
    var def = b2.b2DefaultShapeDef();
    def.density = density;
    def.material.friction = friction;
    def.material.restitution = restitution;
    if (filter) |f| {
        def.filter.categoryBits = f.layer;
        def.filter.maskBits = f.mask;
    }
    return def;
}

/// Attaches a box, offset and rotated relative to the body. Fails with invalid argument for a null
/// vtable or handle and not found when the id does not resolve.
fn addBoxFixture(
    self_in: ?*abi_physics.ke_physics_2d,
    id: abi_physics.ke_body_2d,
    half_w: f32,
    half_h: f32,
    offset_x: f32,
    offset_y: f32,
    offset_angle: f32,
    density: f32,
    friction: f32,
    restitution: f32,
    filter: ?*const abi_physics.ke_collision_filter_2d,
) callconv(.c) abi_result.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const body = lookup(stateOf(self), id) orelse return R.code(error.NotFound);

    const def = makeShapeDef(density, friction, restitution, filter);
    const box = b2.b2MakeOffsetBox(half_w, half_h, .{ .x = offset_x, .y = offset_y }, makeRot(offset_angle));
    _ = b2.b2CreatePolygonShape(body, &def, &box);
    return R.ok;
}

/// Attaches a circle centred at the offset. Fails like `addBoxFixture`.
fn addCircleFixture(
    self_in: ?*abi_physics.ke_physics_2d,
    id: abi_physics.ke_body_2d,
    radius: f32,
    offset_x: f32,
    offset_y: f32,
    density: f32,
    friction: f32,
    restitution: f32,
    filter: ?*const abi_physics.ke_collision_filter_2d,
) callconv(.c) abi_result.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const body = lookup(stateOf(self), id) orelse return R.code(error.NotFound);

    const def = makeShapeDef(density, friction, restitution, filter);
    const circle = b2.b2Circle{ .center = .{ .x = offset_x, .y = offset_y }, .radius = radius };
    _ = b2.b2CreateCircleShape(body, &def, &circle);
    return R.ok;
}

/// The output is zeroed first, so a body that does not resolve reads as an all-zero state.
fn getBodyState(self_in: ?*abi_physics.ke_physics_2d, id: abi_physics.ke_body_2d, out_in: ?*abi_physics.ke_body_state_2d) callconv(.c) void {
    const out = out_in orelse return;
    out.* = std.mem.zeroes(abi_physics.ke_body_state_2d);

    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;

    const p = b2.b2Body_GetPosition(body);
    const v = b2.b2Body_GetLinearVelocity(body);
    out.x = p.x;
    out.y = p.y;
    out.angle = rotAngle(b2.b2Body_GetRotation(body));
    out.velocity_x = v.x;
    out.velocity_y = v.y;
    out.angular_velocity = b2.b2Body_GetAngularVelocity(body);
}

/// Teleports the body to the position and angle, in radians, keeping its velocity.
fn setBodyPosition(self_in: ?*abi_physics.ke_physics_2d, id: abi_physics.ke_body_2d, x: f32, y: f32, angle: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    b2.b2Body_SetTransform(body, .{ .x = x, .y = y }, makeRot(angle));
}

/// Overwrites the body's linear velocity; an id that does not resolve does nothing.
fn setBodyVelocity(self_in: ?*abi_physics.ke_physics_2d, id: abi_physics.ke_body_2d, vx: f32, vy: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    b2.b2Body_SetLinearVelocity(body, .{ .x = vx, .y = vy });
}

/// Applies the impulse to the body's centre and wakes it; an id that does not resolve does
/// nothing.
fn applyImpulse(self_in: ?*abi_physics.ke_physics_2d, id: abi_physics.ke_body_2d, ix: f32, iy: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    b2.b2Body_ApplyLinearImpulseToCenter(body, .{ .x = ix, .y = iy }, true);
}

/// Locks or unlocks the body's rotation; an id that does not resolve does nothing.
fn setBodyFixedRotation(self_in: ?*abi_physics.ke_physics_2d, id: abi_physics.ke_body_2d, fixed: bool) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    b2.b2Body_SetFixedRotation(body, fixed);
}

/// Scales the gravity that acts on the body; an id that does not resolve does nothing.
fn setBodyGravityScale(self_in: ?*abi_physics.ke_physics_2d, id: abi_physics.ke_body_2d, scale: f32) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const body = lookup(stateOf(self), id) orelse return;
    b2.b2Body_SetGravityScale(body, scale);
}

fn makeRot(radians: f32) b2.b2Rot {
    return .{ .c = @cos(radians), .s = @sin(radians) };
}

/// The result is in the range that the standard arctangent returns, so an angle set outside that
/// range reads back as an equivalent angle inside it.
fn rotAngle(q: b2.b2Rot) f32 {
    return std.math.atan2(q.s, q.c);
}

/// Tears down the world, then the body table, then the state, in that order.
fn destroy(self_in: ?*abi_physics.ke_physics_2d) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    b2.b2DestroyWorld(s.world);
    if (s.bodies) |b| heap.gpa.free(b[0..s.body_capacity]);
    heap.gpa.destroy(s);
}

/// Writes the world's handle, or a zeroed one on failure; a failure after the state exists frees
/// the state first. On success the handle's destroy slot releases the world and everything the
/// state owns.
export fn ke_physics_2d_box2d_create(
    params_in: ?*const abi_factory.ke_physics_2d_box2d_params,
    out_world: ?*abi_physics.ke_physics_2d_handle,
) callconv(.c) abi_result.ke_result {
    const out = out_world orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_physics.ke_physics_2d_handle);
    const params = params_in orelse return R.code(error.InvalidArgument);
    out.* = create(params) catch |err| {
        log.warn("creating the physics world failed: {t}", .{err});
        return R.code(err);
    };
    log.info("world initialized", .{});
    return R.ok;
}

fn create(params: *const abi_factory.ke_physics_2d_box2d_params) R.Error!abi_physics.ke_physics_2d_handle {
    const s = heap.gpa.create(State) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(s);
    s.* = .{
        .api = std.mem.zeroes(abi_physics.ke_physics_2d),
        .world = undefined,
        .bodies = null,
        .body_count = 0,
        .body_capacity = 0,
    };

    var world_def = b2.b2DefaultWorldDef();
    world_def.gravity = .{ .x = params.gravity_x, .y = params.gravity_y };
    s.world = b2.b2CreateWorld(&world_def);
    if (!b2.b2World_IsValid(s.world)) return error.General;

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

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;

fn makeWorld(gravity_x: f32, gravity_y: f32) abi_physics.ke_physics_2d_handle {
    var params = std.mem.zeroes(abi_factory.ke_physics_2d_box2d_params);
    params.gravity_x = gravity_x;
    params.gravity_y = gravity_y;
    var h: abi_physics.ke_physics_2d_handle = undefined;
    R.check(ke_physics_2d_box2d_create(&params, &h)) catch return std.mem.zeroes(abi_physics.ke_physics_2d_handle);
    return h;
}

fn newBody(h: abi_physics.ke_physics_2d_handle, body_type: abi_physics.ke_body_type_2d, x: f32, y: f32) !abi_physics.ke_body_2d {
    var body: abi_physics.ke_body_2d = undefined;
    try R.check(h.ref.?.create_body.?(h.ref, body_type, x, y, &body));
    return body;
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

    h.ref.?.set_gravity.?(h.ref, 0.0, -10.0);
}

test "stepping an empty world is accepted" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    h.ref.?.step.?(h.ref, 0.016);
}

test "creating a body returns a handle that is not the invalid sentinel" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    try testing.expect(body != abi_physics.KE_BODY_2D_INVALID);
}

test "a box fixture attaches to an existing body" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    try R.check(h.ref.?.add_box_fixture.?(h.ref, body, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.3, 0.1, null));
}

test "a circle fixture attaches to an existing body" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    try R.check(h.ref.?.add_circle_fixture.?(h.ref, body, 1.0, 0.0, 0.0, 1.0, 0.3, 0.1, null));
}

test "a body reports the position it was created at" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 10.0, 20.0);

    var state = std.mem.zeroes(abi_physics.ke_body_state_2d);
    h.ref.?.get_body_state.?(h.ref, body, &state);

    try testing.expectApproxEqAbs(@as(f32, 10.0), state.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 20.0), state.y, 1e-5);
}

test "setting a body position moves it and sets its angle" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    h.ref.?.set_body_position.?(h.ref, body, 5.0, 5.0, 0.78);

    var state = std.mem.zeroes(abi_physics.ke_body_state_2d);
    h.ref.?.get_body_state.?(h.ref, body, &state);

    try testing.expectApproxEqAbs(@as(f32, 5.0), state.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 5.0), state.y, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.78), state.angle, 1e-5);
}

test "setting a body velocity is readable back before any step" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    h.ref.?.set_body_velocity.?(h.ref, body, 1.0, 2.0);

    var state = std.mem.zeroes(abi_physics.ke_body_state_2d);
    h.ref.?.get_body_state.?(h.ref, body, &state);

    try testing.expectApproxEqAbs(@as(f32, 1.0), state.velocity_x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 2.0), state.velocity_y, 1e-5);
}

test "an impulse pushes a body along both axes it was applied on" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    try R.check(h.ref.?.add_box_fixture.?(h.ref, body, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.3, 0.1, null));
    h.ref.?.apply_impulse.?(h.ref, body, 10.0, 10.0);

    h.ref.?.step.?(h.ref, 0.016);

    var state = std.mem.zeroes(abi_physics.ke_body_state_2d);
    h.ref.?.get_body_state.?(h.ref, body, &state);

    try testing.expect(state.velocity_x > 0.0);
    try testing.expect(state.velocity_y > 0.0);
}

test "destroying a body retires its handle" {
    const h = makeWorld(0.0, -9.81);
    defer h.destroy.?(h.ref);

    const body = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    h.ref.?.destroy_body.?(h.ref, body);

    var state = abi_physics.ke_body_state_2d{
        .x = 42.0,
        .y = 42.0,
        .angle = 42.0,
        .velocity_x = 42.0,
        .velocity_y = 42.0,
        .angular_velocity = 42.0,
    };
    h.ref.?.get_body_state.?(h.ref, body, &state);

    try testing.expectApproxEqAbs(@as(f32, 0.0), state.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.0), state.y, 1e-5);
}

test "a rotation locked box never picks up spin when it bounces off a wall" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall = try newBody(h, abi_physics.KE_BODY_TYPE_STATIC, 2.0, 0.0);
    try testing.expect(wall != abi_physics.KE_BODY_2D_INVALID);
    try R.check(h.ref.?.add_box_fixture.?(h.ref, wall, 0.25, 4.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, null));

    const ball = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    try testing.expect(ball != abi_physics.KE_BODY_2D_INVALID);
    try R.check(h.ref.?.add_box_fixture.?(h.ref, ball, 0.18, 0.18, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, null));
    h.ref.?.set_body_fixed_rotation.?(h.ref, ball, true);
    h.ref.?.set_body_velocity.?(h.ref, ball, 6.0, 0.0);

    var state = std.mem.zeroes(abi_physics.ke_body_state_2d);
    var i: usize = 0;
    while (i < 120) : (i += 1) {
        h.ref.?.step.?(h.ref, 1.0 / 60.0);
        h.ref.?.get_body_state.?(h.ref, ball, &state);
        try testing.expectApproxEqAbs(@as(f32, 0.0), state.angular_velocity, 1e-5);
    }

    try testing.expectApproxEqAbs(@as(f32, 0.0), state.angle, 1e-5);
    try testing.expect(state.velocity_x < 0.0);
}

test "a frictionless circle hitting a wall head on does not start spinning" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall = try newBody(h, abi_physics.KE_BODY_TYPE_STATIC, 2.0, 0.0);
    try R.check(h.ref.?.add_box_fixture.?(h.ref, wall, 0.25, 4.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, null));

    const ball = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    try R.check(h.ref.?.add_circle_fixture.?(h.ref, ball, 0.18, 0.0, 0.0, 1.0, 0.0, 1.0, null));
    h.ref.?.set_body_velocity.?(h.ref, ball, 6.0, 0.0);

    var state = std.mem.zeroes(abi_physics.ke_body_state_2d);
    var i: usize = 0;
    while (i < 120) : (i += 1) {
        h.ref.?.step.?(h.ref, 1.0 / 60.0);
        h.ref.?.get_body_state.?(h.ref, ball, &state);
        try testing.expectApproxEqAbs(@as(f32, 0.0), state.angular_velocity, 1e-3);
    }
}

fn wallAndBall(h: abi_physics.ke_physics_2d_handle, wall_filter: ?*const abi_physics.ke_collision_filter_2d, ball_filter: ?*const abi_physics.ke_collision_filter_2d) !abi_physics.ke_body_2d {
    const wall = try newBody(h, abi_physics.KE_BODY_TYPE_STATIC, 2.0, 0.0);
    try R.check(h.ref.?.add_box_fixture.?(h.ref, wall, 0.25, 4.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, wall_filter));

    const ball = try newBody(h, abi_physics.KE_BODY_TYPE_DYNAMIC, 0.0, 0.0);
    try R.check(h.ref.?.add_box_fixture.?(h.ref, ball, 0.18, 0.18, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, ball_filter));
    h.ref.?.set_body_velocity.?(h.ref, ball, 6.0, 0.0);
    return ball;
}

fn runPast(h: abi_physics.ke_physics_2d_handle, ball: abi_physics.ke_body_2d) abi_physics.ke_body_state_2d {
    var state = std.mem.zeroes(abi_physics.ke_body_state_2d);
    var i: usize = 0;
    while (i < 120) : (i += 1) {
        h.ref.?.step.?(h.ref, 1.0 / 60.0);
    }
    h.ref.?.get_body_state.?(h.ref, ball, &state);
    return state;
}

test "a shape whose mask excludes the other's layer passes straight through it" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall_filter = abi_physics.ke_collision_filter_2d{ .layer = 0b10, .mask = 0b10 };
    const ball_filter = abi_physics.ke_collision_filter_2d{ .layer = 0b01, .mask = 0b01 };
    const ball = try wallAndBall(h, &wall_filter, &ball_filter);

    const state = runPast(h, ball);
    try testing.expect(state.velocity_x > 0.0);
    try testing.expect(state.x > 2.0);
}

test "the same pair collides once each mask names the other's layer" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall_filter = abi_physics.ke_collision_filter_2d{ .layer = 0b10, .mask = 0b11 };
    const ball_filter = abi_physics.ke_collision_filter_2d{ .layer = 0b01, .mask = 0b11 };
    const ball = try wallAndBall(h, &wall_filter, &ball_filter);

    const state = runPast(h, ball);
    try testing.expect(state.velocity_x < 0.0);
}

test "clearing one side of the pair is enough to silence the contact" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const wall_filter = abi_physics.ke_collision_filter_2d{ .layer = 0b10, .mask = 0b11 };
    const ball_filter = abi_physics.ke_collision_filter_2d{ .layer = 0b01, .mask = 0b01 };
    const ball = try wallAndBall(h, &wall_filter, &ball_filter);

    const state = runPast(h, ball);
    try testing.expect(state.x > 2.0);
}

test "a null filter leaves the fixture colliding with everything" {
    const h = makeWorld(0.0, 0.0);
    defer h.destroy.?(h.ref);

    const ball = try wallAndBall(h, null, null);
    const state = runPast(h, ball);
    try testing.expect(state.velocity_x < 0.0);
}

test "creating and destroying a physics world leaves no block allocated" {
    const h = makeWorld(0.0, -9.81);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

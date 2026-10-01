const std = @import("std");
const zm = @import("zmath");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const c = @import("cimport.zig").c;
const heap = @import("heap");

const E = @import("kerror").Errors(c);

/// Which way the camera faces along view-space z.
const Handedness = enum { right, left };

const State = struct {
    api: c.ke_view_space,
    hand: Handedness,
};

fn stateOf(self: *c.ke_view_space) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn vec(v: *const c.ke_vec3, w: f32) zm.Vec {
    return zm.f32x4(v.x, v.y, v.z, w);
}

fn store(out: [*c]c.ke_mat4, m: zm.Mat) void {
    if (out == null) return;
    zm.storeMat(out.*.m[0..16], m);
}

fn viewSpaceParams(self_in: ?*c.ke_view_space) callconv(.c) c.ke_view_space_params {
    const self = self_in orelse return .{ .depth_from_view_z = 0.0 };
    if (self.handle == null) return .{ .depth_from_view_z = 0.0 };
    return .{ .depth_from_view_z = switch (stateOf(self).hand) {
        .right => -1.0,
        .left => 1.0,
    } };
}

fn viewSpaceLookTo(
    self_in: ?*c.ke_view_space,
    eye: [*c]const c.ke_vec3,
    forward: [*c]const c.ke_vec3,
    up: [*c]const c.ke_vec3,
    out_view: [*c]c.ke_mat4,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or eye == null or forward == null or up == null) return;
    const e = vec(eye, 1.0);
    const f = vec(forward, 0.0);
    const u = vec(up, 0.0);
    store(out_view, switch (stateOf(self).hand) {
        .right => zm.lookToRh(e, f, u),
        .left => zm.lookToLh(e, f, u),
    });
}

fn viewSpaceLookAt(
    self_in: ?*c.ke_view_space,
    eye: [*c]const c.ke_vec3,
    target: [*c]const c.ke_vec3,
    up: [*c]const c.ke_vec3,
    out_view: [*c]c.ke_mat4,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or eye == null or target == null or up == null) return;
    const e = vec(eye, 1.0);
    const t = vec(target, 1.0);
    const u = vec(up, 0.0);
    store(out_view, switch (stateOf(self).hand) {
        .right => zm.lookAtRh(e, t, u),
        .left => zm.lookAtLh(e, t, u),
    });
}

fn viewSpaceFromTransform(
    self_in: ?*c.ke_view_space,
    camera_world: [*c]const c.ke_mat4,
    out_view: [*c]c.ke_mat4,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or camera_world == null) return;
    const m = camera_world.*.m;
    const eye = zm.f32x4(m[12], m[13], m[14], 1.0);
    const hand = stateOf(self).hand;

    const unrotated = @abs(m[1]) < 1e-6 and @abs(m[2]) < 1e-6 and @abs(m[4]) < 1e-6 and
        @abs(m[6]) < 1e-6 and @abs(m[8]) < 1e-6 and @abs(m[9]) < 1e-6;
    if (unrotated) {
        const origin = zm.f32x4(0, 0, 0, 1);
        const world_up = zm.f32x4(0, 1, 0, 0);
        store(out_view, switch (hand) {
            .right => zm.lookAtRh(eye, origin, world_up),
            .left => zm.lookAtLh(eye, origin, world_up),
        });
        return;
    }

    const facing: f32 = switch (hand) {
        .right => -1.0,
        .left => 1.0,
    };
    const fwd = zm.f32x4(facing * m[8], facing * m[9], facing * m[10], 0);
    const up = zm.f32x4(m[4], m[5], m[6], 0);
    store(out_view, switch (hand) {
        .right => zm.lookToRh(eye, fwd, up),
        .left => zm.lookToLh(eye, fwd, up),
    });
}

/// Applies the device's clip conventions to a projection: a top-left
/// framebuffer origin negates the y row.
fn intoClip(p_in: zm.Mat, clip: c.ke_ndc_convention) zm.Mat {
    var p = p_in;
    if (clip.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

fn viewSpacePerspective(
    self_in: ?*c.ke_view_space,
    fov_y: f32,
    aspect: f32,
    near_plane: f32,
    far_plane: f32,
    clip_in: [*c]const c.ke_ndc_convention,
    out_proj: [*c]c.ke_mat4,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or clip_in == null) return;
    const clip = clip_in.*;
    const zero_to_one = clip.z_zero_to_one != 0;
    const p = switch (stateOf(self).hand) {
        .right => if (zero_to_one)
            zm.perspectiveFovRh(fov_y, aspect, near_plane, far_plane)
        else
            zm.perspectiveFovRhGl(fov_y, aspect, near_plane, far_plane),
        .left => if (zero_to_one)
            zm.perspectiveFovLh(fov_y, aspect, near_plane, far_plane)
        else
            zm.perspectiveFovLhGl(fov_y, aspect, near_plane, far_plane),
    };
    store(out_proj, intoClip(p, clip));
}

fn viewSpaceOrthographic(
    self_in: ?*c.ke_view_space,
    width: f32,
    height: f32,
    near_plane: f32,
    far_plane: f32,
    clip_in: [*c]const c.ke_ndc_convention,
    out_proj: [*c]c.ke_mat4,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or clip_in == null) return;
    const clip = clip_in.*;
    const zero_to_one = clip.z_zero_to_one != 0;
    const p = switch (stateOf(self).hand) {
        .right => if (zero_to_one)
            zm.orthographicRh(width, height, near_plane, far_plane)
        else
            zm.orthographicRhGl(width, height, near_plane, far_plane),
        .left => if (zero_to_one)
            zm.orthographicLh(width, height, near_plane, far_plane)
        else
            zm.orthographicLhGl(width, height, near_plane, far_plane),
    };
    store(out_proj, intoClip(p, clip));
}

fn destroy(self_in: ?*c.ke_view_space) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    heap.gpa.destroy(stateOf(self));
}

fn create(hand: Handedness, out_error: [*c][*c]c.ke_error) c.ke_view_space_handle {
    const null_handle = std.mem.zeroes(c.ke_view_space_handle);

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = .{ .api = std.mem.zeroes(c.ke_view_space), .hand = hand };
    s.api.handle = s;
    s.api.params = viewSpaceParams;
    s.api.look_to = viewSpaceLookTo;
    s.api.look_at = viewSpaceLookAt;
    s.api.view_from_transform = viewSpaceFromTransform;
    s.api.perspective = viewSpacePerspective;
    s.api.orthographic = viewSpaceOrthographic;

    return .{ .ref = &s.api, .destroy = destroy };
}

export fn ke_view_space_rh_create(
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_view_space_handle {
    return create(.right, out_error);
}

export fn ke_view_space_lh_create(
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_view_space_handle {
    return create(.left, out_error);
}

const testing = std.testing;

const webgpu_clip: c.ke_ndc_convention = .{ .z_zero_to_one = 1, .y_flip = 0, .clip_left_handed = 1 };

fn viewDepthOf(h: c.ke_view_space_handle, world: c.ke_vec3, eye: c.ke_vec3) f32 {
    const target = c.ke_vec3{ .x = 0, .y = 0, .z = 0 };
    const up = c.ke_vec3{ .x = 0, .y = 1, .z = 0 };
    var view: c.ke_mat4 = undefined;
    h.ref.*.look_at.?(h.ref, &eye, &target, &up, &view);
    const m = zm.loadMat(&view.m);
    const p = zm.mul(zm.f32x4(world.x, world.y, world.z, 1.0), m);
    return p[2] * h.ref.*.params.?(h.ref).depth_from_view_z;
}

test "both view spaces report a surface in front of the camera as positive depth" {
    const eye = c.ke_vec3{ .x = 0, .y = 0, .z = 10 };
    const near_point = c.ke_vec3{ .x = 0, .y = 0, .z = 2 };
    const far_point = c.ke_vec3{ .x = 0, .y = 0, .z = -2 };

    inline for (.{ ke_view_space_rh_create, ke_view_space_lh_create }) |factory| {
        const h = factory(null);
        defer h.destroy.?(h.ref);

        const near_depth = viewDepthOf(h, near_point, eye);
        const far_depth = viewDepthOf(h, far_point, eye);

        try testing.expect(near_depth > 0.0);
        try testing.expect(far_depth > near_depth);
    }
}

test "the two view spaces disagree on the sign of view z and only there" {
    const rh = ke_view_space_rh_create(null);
    defer rh.destroy.?(rh.ref);
    const lh = ke_view_space_lh_create(null);
    defer lh.destroy.?(lh.ref);

    try testing.expectEqual(@as(f32, -1.0), rh.ref.*.params.?(rh.ref).depth_from_view_z);
    try testing.expectEqual(@as(f32, 1.0), lh.ref.*.params.?(lh.ref).depth_from_view_z);

    const eye = c.ke_vec3{ .x = 1, .y = 2, .z = 7 };
    const point = c.ke_vec3{ .x = -3, .y = 1, .z = 0.5 };
    try testing.expectApproxEqAbs(viewDepthOf(rh, point, eye), viewDepthOf(lh, point, eye), 1e-4);
}

test "a top-left framebuffer origin flips the projection's y row, whatever the view space" {
    var flipped_clip = webgpu_clip;
    flipped_clip.y_flip = 1;

    inline for (.{ ke_view_space_rh_create, ke_view_space_lh_create }) |factory| {
        const h = factory(null);
        defer h.destroy.?(h.ref);

        var plain: c.ke_mat4 = undefined;
        var flipped: c.ke_mat4 = undefined;
        h.ref.*.perspective.?(h.ref, 1.0, 1.6, 0.1, 100.0, &webgpu_clip, &plain);
        h.ref.*.perspective.?(h.ref, 1.0, 1.6, 0.1, 100.0, &flipped_clip, &flipped);

        try testing.expectEqual(-plain.m[5], flipped.m[5]);
        try testing.expectEqual(plain.m[0], flipped.m[0]);
    }
}

test "a perspective projection puts the near plane at clip zero and the far plane at clip one" {
    inline for (.{ ke_view_space_rh_create, ke_view_space_lh_create }) |factory| {
        const h = factory(null);
        defer h.destroy.?(h.ref);

        var proj: c.ke_mat4 = undefined;
        h.ref.*.perspective.?(h.ref, 1.0, 1.0, 0.5, 50.0, &webgpu_clip, &proj);
        const p = zm.loadMat(&proj.m);

        const sign = h.ref.*.params.?(h.ref).depth_from_view_z;
        const near_v = zm.f32x4(0, 0, 0.5 / sign, 1.0);
        const far_v = zm.f32x4(0, 0, 50.0 / sign, 1.0);
        const near_clip = zm.mul(near_v, p);
        const far_clip = zm.mul(far_v, p);

        try testing.expectApproxEqAbs(@as(f32, 0.0), near_clip[2] / near_clip[3], 1e-3);
        try testing.expectApproxEqAbs(@as(f32, 1.0), far_clip[2] / far_clip[3], 1e-3);
    }
}

test "every slot tolerates a null self instead of faulting on it" {
    var out: c.ke_mat4 = std.mem.zeroes(c.ke_mat4);
    const zero = c.ke_vec3{ .x = 0, .y = 0, .z = 0 };

    viewSpaceLookTo(null, &zero, &zero, &zero, &out);
    viewSpaceLookAt(null, &zero, &zero, &zero, &out);
    viewSpaceFromTransform(null, null, &out);
    viewSpacePerspective(null, 1.0, 1.0, 0.1, 10.0, &webgpu_clip, &out);
    viewSpaceOrthographic(null, 1.0, 1.0, 0.1, 10.0, &webgpu_clip, &out);

    try testing.expectEqual(@as(f32, 0.0), viewSpaceParams(null).depth_from_view_z);
    try testing.expectEqual(@as(f32, 0.0), out.m[0]);
}

test "a null output matrix is dropped rather than written through" {
    const h = ke_view_space_rh_create(null);
    defer h.destroy.?(h.ref);

    const zero = c.ke_vec3{ .x = 0, .y = 0, .z = 0 };
    const up = c.ke_vec3{ .x = 0, .y = 1, .z = 0 };
    h.ref.*.look_at.?(h.ref, &up, &zero, &up, null);
    h.ref.*.perspective.?(h.ref, 1.0, 1.0, 0.1, 10.0, &webgpu_clip, null);
}

test "a missing clip convention leaves the projection untouched" {
    const h = ke_view_space_rh_create(null);
    defer h.destroy.?(h.ref);

    var out: c.ke_mat4 = std.mem.zeroes(c.ke_mat4);
    h.ref.*.perspective.?(h.ref, 1.0, 1.0, 0.1, 10.0, null, &out);
    try testing.expectEqual(@as(f32, 0.0), out.m[0]);
}

fn cameraLookingDown(axis: c.ke_vec3, from: c.ke_vec3) c.ke_mat4 {
    const f = zm.normalize3(zm.f32x4(axis.x, axis.y, axis.z, 0));
    const world_up = zm.f32x4(0, 1, 0, 0);
    const right = zm.normalize3(zm.cross3(world_up, f));
    const up = zm.cross3(f, right);
    var m: c.ke_mat4 = std.mem.zeroes(c.ke_mat4);
    m.m[0] = right[0];  m.m[1] = right[1];  m.m[2] = right[2];
    m.m[4] = up[0];     m.m[5] = up[1];     m.m[6] = up[2];
    m.m[8] = f[0];      m.m[9] = f[1];      m.m[10] = f[2];
    m.m[12] = from.x;   m.m[13] = from.y;   m.m[14] = from.z;
    m.m[15] = 1.0;
    return m;
}

test "the same camera basis faces opposite ways under the two view spaces" {
    const local_z = c.ke_vec3{ .x = 1, .y = 0, .z = 0 };
    const at_origin = c.ke_vec3{ .x = 0, .y = 0, .z = 0 };
    const world = cameraLookingDown(local_z, at_origin);
    const toward_plus_x = zm.f32x4(6, 0, 0, 1);

    const rh = ke_view_space_rh_create(null);
    defer rh.destroy.?(rh.ref);
    const lh = ke_view_space_lh_create(null);
    defer lh.destroy.?(lh.ref);

    var rh_view: c.ke_mat4 = undefined;
    var lh_view: c.ke_mat4 = undefined;
    rh.ref.*.view_from_transform.?(rh.ref, &world, &rh_view);
    lh.ref.*.view_from_transform.?(lh.ref, &world, &lh_view);

    const rh_depth = zm.mul(toward_plus_x, zm.loadMat(&rh_view.m))[2] *
        rh.ref.*.params.?(rh.ref).depth_from_view_z;
    const lh_depth = zm.mul(toward_plus_x, zm.loadMat(&lh_view.m))[2] *
        lh.ref.*.params.?(lh.ref).depth_from_view_z;

    try testing.expect(lh_depth > 0.0);
    try testing.expect(rh_depth < 0.0);
    try testing.expectApproxEqAbs(lh_depth, -rh_depth, 1e-3);
}

test "turning a camera around swaps which side of it is visible" {
    const local_z = c.ke_vec3{ .x = 1, .y = 0, .z = 0 };
    const flipped_z = c.ke_vec3{ .x = -1, .y = 0, .z = 0 };
    const at_origin = c.ke_vec3{ .x = 0, .y = 0, .z = 0 };
    const point = zm.f32x4(6, 0, 0, 1);

    inline for (.{ ke_view_space_rh_create, ke_view_space_lh_create }) |factory| {
        const h = factory(null);
        defer h.destroy.?(h.ref);
        const sign = h.ref.*.params.?(h.ref).depth_from_view_z;

        const facing = cameraLookingDown(local_z, at_origin);
        const turned = cameraLookingDown(flipped_z, at_origin);

        var a: c.ke_mat4 = undefined;
        var b: c.ke_mat4 = undefined;
        h.ref.*.view_from_transform.?(h.ref, &facing, &a);
        h.ref.*.view_from_transform.?(h.ref, &turned, &b);

        const da = zm.mul(point, zm.loadMat(&a.m))[2] * sign;
        const db = zm.mul(point, zm.loadMat(&b.m))[2] * sign;
        try testing.expect(da * db < 0.0);
    }
}

test "an unrotated camera basis aims at the world origin rather than at nothing" {
    var world: c.ke_mat4 = std.mem.zeroes(c.ke_mat4);
    world.m[0] = 1.0;
    world.m[5] = 1.0;
    world.m[10] = 1.0;
    world.m[14] = 8.0;
    world.m[15] = 1.0;

    inline for (.{ ke_view_space_rh_create, ke_view_space_lh_create }) |factory| {
        const h = factory(null);
        defer h.destroy.?(h.ref);

        var view: c.ke_mat4 = undefined;
        h.ref.*.view_from_transform.?(h.ref, &world, &view);
        const m = zm.loadMat(&view.m);
        const sign = h.ref.*.params.?(h.ref).depth_from_view_z;

        const origin_depth = zm.mul(zm.f32x4(0, 0, 0, 1), m)[2] * sign;
        try testing.expectApproxEqAbs(@as(f32, 8.0), origin_depth, 1e-3);
    }
}

fn cameraAt(z: f32) c.ke_mat4 {
    var world: c.ke_mat4 = std.mem.zeroes(c.ke_mat4);
    world.m[0] = 1.0;
    world.m[5] = 1.0;
    world.m[10] = 1.0;
    world.m[14] = z;
    world.m[15] = 1.0;
    return world;
}

fn ndcOf(h: c.ke_view_space_handle, world: c.ke_mat4, half_height: f32, aspect: f32, p: zm.Vec) zm.Vec {
    var view: c.ke_mat4 = undefined;
    var proj: c.ke_mat4 = undefined;
    h.ref.*.view_from_transform.?(h.ref, &world, &view);
    const height = half_height * 2.0;
    h.ref.*.orthographic.?(h.ref, height * aspect, height, 0.1, 100.0, &webgpu_clip, &proj);
    const clip = zm.mul(zm.mul(p, zm.loadMat(&view.m)), zm.loadMat(&proj.m));
    return clip / zm.f32x4s(clip[3]);
}

test "an orthographic camera keeps every corner of its authored half-extent on screen" {
    const h = ke_view_space_rh_create(null);
    defer h.destroy.?(h.ref);

    const world = cameraAt(10.0);
    const half_height: f32 = 5.0;
    const aspect: f32 = 16.0 / 9.0;

    const corners = [_]zm.Vec{
        zm.f32x4(0, 4.5, 0, 1),
        zm.f32x4(0, -4.5, 0, 1),
        zm.f32x4(-7.5, 0, 0, 1),
        zm.f32x4(7.5, 0, 0, 1),
        zm.f32x4(0, 0, 0, 1),
    };

    for (corners) |p| {
        const n = ndcOf(h, world, half_height, aspect, p);
        try testing.expect(n[0] >= -1.0 and n[0] <= 1.0);
        try testing.expect(n[1] >= -1.0 and n[1] <= 1.0);
        try testing.expect(n[2] >= 0.0 and n[2] <= 1.0);
    }
}

test "an orthographic camera separates a point above its centre from one below" {
    const h = ke_view_space_rh_create(null);
    defer h.destroy.?(h.ref);

    const world = cameraAt(10.0);
    const above = ndcOf(h, world, 5.0, 16.0 / 9.0, zm.f32x4(0, 4.5, 0, 1));
    const below = ndcOf(h, world, 5.0, 16.0 / 9.0, zm.f32x4(0, -4.5, 0, 1));
    const left = ndcOf(h, world, 5.0, 16.0 / 9.0, zm.f32x4(-7.5, 0, 0, 1));
    const right = ndcOf(h, world, 5.0, 16.0 / 9.0, zm.f32x4(7.5, 0, 0, 1));

    try testing.expectApproxEqAbs(above[1], -below[1], 1e-4);
    try testing.expectApproxEqAbs(left[0], -right[0], 1e-4);
    try testing.expect(above[1] > 0.0);
    try testing.expect(right[0] > 0.0);
}

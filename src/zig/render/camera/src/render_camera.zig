const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("cimport.zig").c;
const heap = @import("heap");

const E = @import("kerror").Errors(c);

const State = struct {
    api: c.ke_render_camera,
    view_space: *c.ke_view_space,
    clip: c.ke_ndc_convention,
};

fn stateOf(self: *c.ke_render_camera) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn viewOf(s: *State, camera_world: [*c]const c.ke_mat4, out_view: [*c]c.ke_mat4) void {
    const from_transform = s.view_space.view_from_transform orelse return;
    from_transform(s.view_space, camera_world, out_view);
}

fn cameraView(
    self_in: ?*c.ke_render_camera,
    camera_world: [*c]const c.ke_mat4,
    out_view: [*c]c.ke_mat4,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or camera_world == null or out_view == null) return;
    viewOf(stateOf(self), camera_world, out_view);
}

fn cameraViewRotation(
    self_in: ?*c.ke_render_camera,
    camera_world: [*c]const c.ke_mat4,
    out_view: [*c]c.ke_mat4,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or camera_world == null or out_view == null) return;
    viewOf(stateOf(self), camera_world, out_view);
    const m: *[16]f32 = &out_view.*.m;
    m[12] = 0;
    m[13] = 0;
    m[14] = 0;
}

fn perspective(s: *State, camera: [*c]const c.ke_camera_component, aspect: f32, out_proj: [*c]c.ke_mat4) void {
    const build = s.view_space.perspective orelse return;
    const fov_y = camera.*.fov * std.math.rad_per_deg;
    build(s.view_space, fov_y, aspect, camera.*.near_plane, camera.*.far_plane, &s.clip, out_proj);
}

fn cameraProjection(
    self_in: ?*c.ke_render_camera,
    camera: [*c]const c.ke_camera_component,
    aspect: f32,
    out_proj: [*c]c.ke_mat4,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or camera == null or out_proj == null) return;
    const s = stateOf(self);

    if (camera.*.orthographic != 0) {
        const build = s.view_space.orthographic orelse return;
        const height = camera.*.orthographic_size * 2.0;
        build(s.view_space, height * aspect, height, camera.*.near_plane, camera.*.far_plane, &s.clip, out_proj);
        return;
    }
    perspective(s, camera, aspect, out_proj);
}

fn cameraPerspectiveProjection(
    self_in: ?*c.ke_render_camera,
    camera: [*c]const c.ke_camera_component,
    aspect: f32,
    out_proj: [*c]c.ke_mat4,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or camera == null or out_proj == null) return;
    perspective(stateOf(self), camera, aspect, out_proj);
}

fn cameraPerspectiveFrustum(
    self_in: ?*c.ke_render_camera,
    camera: [*c]const c.ke_camera_component,
    aspect: f32,
    out_frustum: [*c]c.ke_camera_frustum,
) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null or camera == null or out_frustum == null) return;
    out_frustum.* = .{
        .tan_half_fov_y = std.math.tan(camera.*.fov * std.math.rad_per_deg * 0.5),
        .aspect = aspect,
        .near_plane = camera.*.near_plane,
        .far_plane = camera.*.far_plane,
    };
}

fn destroy(self_in: ?*c.ke_render_camera) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    heap.gpa.destroy(stateOf(self));
}

export fn ke_render_camera_create(
    view_space: ?*c.ke_view_space,
    clip: [*c]const c.ke_ndc_convention,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_render_camera_handle {
    const null_handle = std.mem.zeroes(c.ke_render_camera_handle);

    const vs = view_space orelse {
        E.fail(out_error, .invalid_argument, "view_space is required", @src());
        return null_handle;
    };
    if (clip == null) {
        E.fail(out_error, .invalid_argument, "clip is required", @src());
        return null_handle;
    }

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = .{ .api = std.mem.zeroes(c.ke_render_camera), .view_space = vs, .clip = clip.* };
    s.api.handle = s;
    s.api.view = cameraView;
    s.api.view_rotation = cameraViewRotation;
    s.api.projection = cameraProjection;
    s.api.perspective_projection = cameraPerspectiveProjection;
    s.api.perspective_frustum = cameraPerspectiveFrustum;

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;

const Recorded = struct {
    calls: u32 = 0,
    first: f32 = 0,
    second: f32 = 0,
    near: f32 = 0,
    far: f32 = 0,
    clip_seen: c.ke_ndc_convention = std.mem.zeroes(c.ke_ndc_convention),
};

var orthographic_call: Recorded = .{};
var perspective_call: Recorded = .{};
var view_world_seen: c.ke_mat4 = std.mem.zeroes(c.ke_mat4);
var view_calls: u32 = 0;

fn fakeOrthographic(_: ?*c.ke_view_space, width: f32, height: f32, near_plane: f32, far_plane: f32, clip: [*c]const c.ke_ndc_convention, _: [*c]c.ke_mat4) callconv(.c) void {
    orthographic_call = .{ .calls = orthographic_call.calls + 1, .first = width, .second = height, .near = near_plane, .far = far_plane, .clip_seen = clip.* };
}

fn fakePerspective(_: ?*c.ke_view_space, fov_y: f32, aspect: f32, near_plane: f32, far_plane: f32, clip: [*c]const c.ke_ndc_convention, _: [*c]c.ke_mat4) callconv(.c) void {
    perspective_call = .{ .calls = perspective_call.calls + 1, .first = fov_y, .second = aspect, .near = near_plane, .far = far_plane, .clip_seen = clip.* };
}

fn fakeViewFromTransform(_: ?*c.ke_view_space, camera_world: [*c]const c.ke_mat4, out_view: [*c]c.ke_mat4) callconv(.c) void {
    view_calls += 1;
    view_world_seen = camera_world.*;
    const m: *[16]f32 = &out_view.*.m;
    for (m, 0..) |*slot, i| slot.* = @floatFromInt(i + 1);
}

const Fixture = struct {
    view_space: c.ke_view_space,
    clip: c.ke_ndc_convention,
    handle: c.ke_render_camera_handle,

    fn init(self: *Fixture) void {
        orthographic_call = .{};
        perspective_call = .{};
        view_calls = 0;
        self.view_space = std.mem.zeroes(c.ke_view_space);
        self.view_space.orthographic = &fakeOrthographic;
        self.view_space.perspective = &fakePerspective;
        self.view_space.view_from_transform = &fakeViewFromTransform;
        self.clip = .{ .z_zero_to_one = 1, .y_flip = 1, .clip_left_handed = 0 };
        self.handle = ke_render_camera_create(&self.view_space, &self.clip, null);
    }

    fn api(self: *Fixture) *c.ke_render_camera {
        return self.handle.ref.?;
    }

    fn deinit(self: *Fixture) void {
        self.handle.destroy.?(self.handle.ref);
    }
};

fn makeCamera(fov: f32, orthographic: bool, size: f32) c.ke_camera_component {
    var cam = std.mem.zeroes(c.ke_camera_component);
    cam.fov = fov;
    cam.near_plane = 0.5;
    cam.far_plane = 50;
    cam.orthographic_size = size;
    cam.orthographic = @intFromBool(orthographic);
    return cam;
}

test "an orthographic camera asks for a box twice its size tall and aspect times that wide" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    var cam = makeCamera(60, true, 5);
    var proj: c.ke_mat4 = undefined;
    f.api().projection.?(f.api(), &cam, 2, &proj);

    try testing.expectEqual(@as(u32, 1), orthographic_call.calls);
    try testing.expectEqual(@as(u32, 0), perspective_call.calls);
    try testing.expectEqual(@as(f32, 20), orthographic_call.first);
    try testing.expectEqual(@as(f32, 10), orthographic_call.second);
    try testing.expectEqual(@as(f32, 0.5), orthographic_call.near);
    try testing.expectEqual(@as(f32, 50), orthographic_call.far);
}

test "a perspective camera hands its field of view over in radians" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    var cam = makeCamera(90, false, 5);
    var proj: c.ke_mat4 = undefined;
    f.api().projection.?(f.api(), &cam, 1.5, &proj);

    try testing.expectEqual(@as(u32, 0), orthographic_call.calls);
    try testing.expectEqual(@as(u32, 1), perspective_call.calls);
    try testing.expectApproxEqAbs(std.math.pi / 2.0, perspective_call.first, 1e-6);
    try testing.expectEqual(@as(f32, 1.5), perspective_call.second);
}

test "the perspective projection ignores a camera's orthographic flag" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    var cam = makeCamera(90, true, 5);
    var proj: c.ke_mat4 = undefined;
    f.api().perspective_projection.?(f.api(), &cam, 1, &proj);

    try testing.expectEqual(@as(u32, 0), orthographic_call.calls);
    try testing.expectEqual(@as(u32, 1), perspective_call.calls);
}

test "projections are built in the clip convention the camera was created with" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    f.clip.y_flip = 0;
    var cam = makeCamera(60, false, 5);
    var proj: c.ke_mat4 = undefined;
    f.api().projection.?(f.api(), &cam, 1, &proj);

    try testing.expectEqual(@as(u8, 1), perspective_call.clip_seen.y_flip);
}

test "the view is the view space's view of the camera's world transform" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    var world = std.mem.zeroes(c.ke_mat4);
    world.m[12] = 4;
    var view: c.ke_mat4 = undefined;
    f.api().view.?(f.api(), &world, &view);

    try testing.expectEqual(@as(u32, 1), view_calls);
    try testing.expectEqual(@as(f32, 4), view_world_seen.m[12]);
    try testing.expectEqual(@as(f32, 13), view.m[12]);
}

test "the rotation-only view drops the translation and keeps the rest" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    var world = std.mem.zeroes(c.ke_mat4);
    var view: c.ke_mat4 = undefined;
    f.api().view_rotation.?(f.api(), &world, &view);

    try testing.expectEqual(@as(f32, 0), view.m[12]);
    try testing.expectEqual(@as(f32, 0), view.m[13]);
    try testing.expectEqual(@as(f32, 0), view.m[14]);
    try testing.expectEqual(@as(f32, 12), view.m[11]);
    try testing.expectEqual(@as(f32, 16), view.m[15]);
}

test "the perspective frustum of a ninety degree camera has a half-angle tangent of one" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    var cam = makeCamera(90, true, 5);
    var frustum: c.ke_camera_frustum = undefined;
    f.api().perspective_frustum.?(f.api(), &cam, 2, &frustum);

    try testing.expectApproxEqAbs(@as(f32, 1), frustum.tan_half_fov_y, 1e-6);
    try testing.expectEqual(@as(f32, 2), frustum.aspect);
    try testing.expectEqual(@as(f32, 0.5), frustum.near_plane);
    try testing.expectEqual(@as(f32, 50), frustum.far_plane);
}

test "every slot tolerates a null self, a null input and a null output" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    const api = f.api();
    var cam = makeCamera(60, false, 5);
    var world = std.mem.zeroes(c.ke_mat4);
    var mat = std.mem.zeroes(c.ke_mat4);
    var frustum = std.mem.zeroes(c.ke_camera_frustum);

    api.view.?(null, &world, &mat);
    api.view.?(api, null, &mat);
    api.view.?(api, &world, null);
    api.view_rotation.?(null, &world, &mat);
    api.view_rotation.?(api, null, &mat);
    api.view_rotation.?(api, &world, null);
    api.projection.?(null, &cam, 1, &mat);
    api.projection.?(api, null, 1, &mat);
    api.projection.?(api, &cam, 1, null);
    api.perspective_projection.?(null, &cam, 1, &mat);
    api.perspective_projection.?(api, null, 1, &mat);
    api.perspective_projection.?(api, &cam, 1, null);
    api.perspective_frustum.?(null, &cam, 1, &frustum);
    api.perspective_frustum.?(api, null, 1, &frustum);
    api.perspective_frustum.?(api, &cam, 1, null);

    try testing.expectEqual(@as(u32, 0), view_calls);
    try testing.expectEqual(@as(u32, 0), orthographic_call.calls + perspective_call.calls);
    try testing.expectEqual(@as(f32, 0), mat.m[0]);
    try testing.expectEqual(@as(f32, 0), frustum.aspect);
}

test "creation without a view space or a clip convention fails with no handle" {
    var vs = std.mem.zeroes(c.ke_view_space);
    var clip = std.mem.zeroes(c.ke_ndc_convention);

    const no_view_space = ke_render_camera_create(null, &clip, null);
    try testing.expect(no_view_space.ref == null);
    const no_clip = ke_render_camera_create(&vs, null, null);
    try testing.expect(no_clip.ref == null);
}

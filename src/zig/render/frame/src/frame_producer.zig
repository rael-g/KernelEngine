//! The first render-phase system of a frame: it begins the frame on the service, then derives the
//! frame globals and the scene's light from the camera and the lights, once for every pass.

const std = @import("std");
const zm = @import("zmath");
const c = @import("c");

/// What the system reads besides its queries: the service it publishes to, the camera that turns
/// a camera entity into matrices, and the seconds elapsed since the first frame.
pub const State = struct {
    core: *c.ke_render_service,
    camera: *c.ke_render_camera,
    time: f64 = 0,
};

/// Index of each query the system is registered with.
pub const camera_query = 0;
pub const light_query = 1;
pub const ambient_query = 2;

/// The system body: begins the frame, then publishes the frame globals and the light. Without a
/// camera the matrices keep their last values while time, dt and viewport still advance. A failed
/// `begin_frame` returns false with the service's error.
pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const st: *State = @alignCast(@ptrCast(user.?));
    const core = st.core;
    if (!core.*.begin_frame.?(core, out_error)) return false;
    st.time += dt;

    var bw: u32 = 0;
    var bh: u32 = 0;
    core.*.backbuffer_size.?(core, &bw, &bh);
    var globals = core.*.frame_globals.?(core).*;
    globals.time = @floatCast(st.time);
    globals.dt = dt;
    globals.viewport = .{ @floatFromInt(bw), @floatFromInt(bh), 0.0, 0.0 };

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, camera_query, &cam_segc);
    if (cam_segc != 0 and cam_segs[0].count != 0) {
        const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
        const cam_wt: *const c.ke_world_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));
        const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;
        var view_m: c.ke_mat4 = undefined;
        st.camera.view.?(st.camera, &cam_wt.matrix, &view_m);
        var proj_m: c.ke_mat4 = undefined;
        st.camera.projection.?(st.camera, cam, aspect, &proj_m);
        const view = zm.loadMat(&view_m.m);
        const proj = zm.loadMat(&proj_m.m);
        const view_proj = zm.mul(view, proj);
        zm.storeMat(globals.view[0..], view);
        zm.storeMat(globals.proj[0..], proj);
        zm.storeMat(globals.view_proj[0..], view_proj);
        zm.storeMat(globals.inv_view_proj[0..], zm.inverse(view_proj));
        zm.storeMat(globals.inv_proj[0..], zm.inverse(proj));
        globals.camera_pos = .{ cam_wt.matrix.m[12], cam_wt.matrix.m[13], cam_wt.matrix.m[14], 1.0 };
        globals.near_plane = cam.near_plane;
        globals.far_plane = cam.far_plane;
    }
    core.*.set_frame_globals.?(core, &globals);

    var lighting = std.mem.zeroes(c.ke_render_lighting);
    var li_segc: usize = 0;
    const li_segs = ctx.?.view.?(ctx, light_query, &li_segc);
    if (li_segc != 0 and li_segs[0].count != 0) {
        const d: *const c.ke_directional_light_component = @ptrCast(@alignCast(li_segs[0].columns[0]));
        lighting.direction = .{ d.direction.x, d.direction.y, d.direction.z, 1.0 };
        lighting.color = .{ d.color.x, d.color.y, d.color.z, d.intensity };
        lighting.ambient = .{ d.ambient.x, d.ambient.y, d.ambient.z, 0.0 };
    }
    var am_segc: usize = 0;
    const am_segs = ctx.?.view.?(ctx, ambient_query, &am_segc);
    if (am_segc != 0 and am_segs[0].count != 0) {
        const al: *const c.ke_ambient_light_component = @ptrCast(@alignCast(am_segs[0].columns[0]));
        lighting.ambient = .{ al.color.x, al.color.y, al.color.z, 0.0 };
    }
    core.*.set_lighting.?(core, &lighting);
    return true;
}

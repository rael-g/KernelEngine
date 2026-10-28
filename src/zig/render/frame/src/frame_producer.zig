//! The first render-phase system of a frame: it begins the frame on the service, then derives the
//! frame globals and the scene's light from the camera and the lights, once for every pass.

const std = @import("std");
const zm = @import("zmath");
const abi_math = @import("abi_math");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_frame);

/// What the system reads besides its queries: the service it publishes to, the camera that turns
/// a camera entity into matrices, and the seconds elapsed since the first frame.
pub const State = struct {
    core: *abi_render.ke_render_service,
    camera: *abi_render.ke_render_camera,
    time: f64 = 0,
};

/// Index of each query the system is registered with.
pub const camera_query = 0;
pub const light_query = 1;
pub const ambient_query = 2;

/// The system body: begins the frame, then publishes the frame globals and the light. Without a
/// camera the matrices keep their last values while time, dt and viewport still advance. A failed
/// `begin_frame` fails the body with the service's code.
pub fn system(ctx: ?*abi_runtime.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) abi_result.ke_result {
    const st: *State = @alignCast(@ptrCast(user.?));
    const core = st.core;
    const began = core.*.begin_frame.?(core);
    if (began != R.ok) return began;
    st.time += dt;

    var bw: u32 = 0;
    var bh: u32 = 0;
    core.*.backbuffer_size.?(core, &bw, &bh);
    var globals = core.*.frame_globals.?(core).?.*;
    globals.time = @floatCast(st.time);
    globals.dt = dt;
    globals.viewport = .{ @floatFromInt(bw), @floatFromInt(bh), 0.0, 0.0 };

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, camera_query, &cam_segc);
    if (cam_segc != 0 and cam_segs.?[0].count != 0) {
        const cam: *const abi_render.ke_camera_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[0]));
        const cam_wt: *const abi_spatial.ke_world_transform_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[1]));
        const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;
        var view_m: abi_math.ke_mat4 = undefined;
        st.camera.view.?(st.camera, &cam_wt.matrix, &view_m);
        var proj_m: abi_math.ke_mat4 = undefined;
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

    var lighting = std.mem.zeroes(abi_render.ke_render_lighting);
    var li_segc: usize = 0;
    const li_segs = ctx.?.view.?(ctx, light_query, &li_segc);
    if (li_segc != 0 and li_segs.?[0].count != 0) {
        const d: *const abi_render.ke_directional_light_component = @ptrCast(@alignCast(li_segs.?[0].columns.?[0]));
        lighting.direction = .{ d.direction.x, d.direction.y, d.direction.z, 1.0 };
        lighting.color = .{ d.color.x, d.color.y, d.color.z, d.intensity };
        lighting.ambient = .{ d.ambient.x, d.ambient.y, d.ambient.z, 0.0 };
    }
    var am_segc: usize = 0;
    const am_segs = ctx.?.view.?(ctx, ambient_query, &am_segc);
    if (am_segc != 0 and am_segs.?[0].count != 0) {
        const al: *const abi_render.ke_ambient_light_component = @ptrCast(@alignCast(am_segs.?[0].columns.?[0]));
        lighting.ambient = .{ al.color.x, al.color.y, al.color.z, 0.0 };
    }
    core.*.set_lighting.?(core, &lighting);
    return R.ok;
}

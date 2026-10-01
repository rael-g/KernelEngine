const std = @import("std");

pub fn Camera(comptime c: type) type {
    return struct {
        pub fn projection(
            cam: *const c.ke_camera_component,
            aspect: f32,
            view_space: *c.ke_view_space,
            clip: *const c.ke_ndc_convention,
            out_proj: *c.ke_mat4,
        ) void {
            if (cam.orthographic != 0) {
                const height = cam.orthographic_size * 2.0;
                view_space.orthographic.?(view_space, height * aspect, height, cam.near_plane, cam.far_plane, clip, out_proj);
                return;
            }

            const fov_y = cam.fov * std.math.rad_per_deg;
            view_space.perspective.?(view_space, fov_y, aspect, cam.near_plane, cam.far_plane, clip, out_proj);
        }
    };
}

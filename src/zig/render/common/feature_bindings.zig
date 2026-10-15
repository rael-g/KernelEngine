//! The bindings a lit pass gives the lighting features its shader declares outside any block: the
//! directional shadow, the environment and the clustered lights, from what their passes published.

/// The buffer names the cluster pass publishes its light lists and grid under, beside the name of
/// the shader parameter each one is bound to.
pub const cluster_buffers = [_]struct { resource: [*:0]const u8, parameter: [*:0]const u8 }{
    .{ .resource = "cluster_point_lights", .parameter = "point_lights" },
    .{ .resource = "cluster_spot_lights", .parameter = "spot_lights" },
    .{ .resource = "cluster_point_indices", .parameter = "point_indices" },
    .{ .resource = "cluster_point_counts", .parameter = "point_counts" },
    .{ .resource = "cluster_spot_indices", .parameter = "spot_indices" },
    .{ .resource = "cluster_spot_counts", .parameter = "spot_counts" },
    .{ .resource = "cluster_grid", .parameter = "cluster" },
};

/// The feature bindings for the C namespace `c`.
pub fn FeatureBindings(comptime c: type) type {
    return struct {
        pub const count = 3 + cluster_buffers.len;

        /// Fills `out` with every feature binding. The shadow map is the white texture when the
        /// service has none, and `environment` is the view the environment is sampled from.
        pub fn fill(core: *c.ke_render_service, environment: c.ke_gpu_texture_view, out: *[count]c.ke_render_shader_binding) void {
            const white_view = core.*.texture_view.?(core, core.*.white_texture.?(core));
            const shadow_raw = core.*.resource_view.?(core, "shadow_map");
            const shadow_view = if (shadow_raw != c.KE_GPU_INVALID_HANDLE) shadow_raw else white_view;
            out[0] = binding("shadowParams");
            out[0].buffer = core.*.resource_buffer.?(core, "shadow_lvp");
            out[0].buffer_size = core.*.resource_buffer_size.?(core, "shadow_lvp");
            out[1] = binding("shadowMap");
            out[1].texture_view = shadow_view;
            out[2] = binding("ibl_env");
            out[2].texture_view = environment;
            for (cluster_buffers, out[3..]) |cb, *o| {
                o.* = binding(cb.parameter);
                o.buffer = core.*.resource_buffer.?(core, cb.resource);
                o.buffer_size = core.*.resource_buffer_size.?(core, cb.resource);
            }
        }

        fn binding(name: [*:0]const u8) c.ke_render_shader_binding {
            return .{ .name = name, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = 0 };
        }
    };
}

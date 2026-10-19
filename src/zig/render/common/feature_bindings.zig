//! The bindings a lit pass gives the lighting features its shader declares outside any block: the
//! directional shadow, the environment and the clustered lights, from what their passes published.
//! A feature pass publishes its resources under one group name the host gives it, with the
//! suffixes of `kernel_engine/render/resource_groups.h`, and a lit pass is given the same name.

/// The longest resource name a group and its suffix make.
pub const name_capacity = 256;

/// Writes `group` followed by `suffix` into `buf`, terminated; null when it does not fit.
pub fn subName(buf: *[name_capacity]u8, group: [*:0]const u8, suffix: []const u8) ?[*:0]const u8 {
    const std = @import("std");
    const made = std.fmt.bufPrintZ(buf, "{s}{s}", .{ std.mem.span(group), suffix }) catch return null;
    return made.ptr;
}

/// The feature bindings for the C namespace `c`, which must include
/// `kernel_engine/render/resource_groups.h`.
pub fn FeatureBindings(comptime c: type) type {
    return struct {
        /// The suffixes the cluster pass publishes its light lists and grid under, beside the name
        /// of the shader parameter each one is bound to.
        pub const cluster_buffers = [_]struct { suffix: []const u8, parameter: [*:0]const u8 }{
            .{ .suffix = c.KE_RENDER_CLUSTER_POINT_LIGHTS, .parameter = "point_lights" },
            .{ .suffix = c.KE_RENDER_CLUSTER_SPOT_LIGHTS, .parameter = "spot_lights" },
            .{ .suffix = c.KE_RENDER_CLUSTER_POINT_INDICES, .parameter = "point_indices" },
            .{ .suffix = c.KE_RENDER_CLUSTER_POINT_COUNTS, .parameter = "point_counts" },
            .{ .suffix = c.KE_RENDER_CLUSTER_SPOT_INDICES, .parameter = "spot_indices" },
            .{ .suffix = c.KE_RENDER_CLUSTER_SPOT_COUNTS, .parameter = "spot_counts" },
            .{ .suffix = c.KE_RENDER_CLUSTER_GRID, .parameter = "cluster" },
        };

        pub const count = 3 + cluster_buffers.len;

        /// Fills `out` with every feature binding, from the shadow group `shadow` and the cluster
        /// group `clusters`. A missing group, or a resource its group did not publish, binds the
        /// neutral value: the white texture for the shadow map and no buffer otherwise.
        /// `environment` is the view the environment is sampled from.
        pub fn fill(core: *c.ke_render_service, environment: c.ke_gpu_texture_view, shadow: ?[*:0]const u8, clusters: ?[*:0]const u8, out: *[count]c.ke_render_shader_binding) void {
            var buf: [name_capacity]u8 = undefined;
            const white_view = core.*.texture_view.?(core, core.*.white_texture.?(core));
            const shadow_raw = if (shadow) |g| core.*.resource_view.?(core, g) else c.KE_GPU_INVALID_HANDLE;
            out[0] = binding("shadowParams");
            const light = if (shadow) |g| subName(&buf, g, c.KE_RENDER_SHADOW_LIGHT) else null;
            if (light) |name| {
                out[0].buffer = core.*.resource_buffer.?(core, name);
                out[0].buffer_size = core.*.resource_buffer_size.?(core, name);
            }
            out[1] = binding("shadowMap");
            out[1].texture_view = if (shadow_raw != c.KE_GPU_INVALID_HANDLE) shadow_raw else white_view;
            out[2] = binding("ibl_env");
            out[2].texture_view = environment;
            for (cluster_buffers, out[3..]) |cb, *o| {
                o.* = binding(cb.parameter);
                const g = clusters orelse continue;
                const name = subName(&buf, g, cb.suffix) orelse continue;
                o.buffer = core.*.resource_buffer.?(core, name);
                o.buffer_size = core.*.resource_buffer_size.?(core, name);
            }
        }

        fn binding(name: [*:0]const u8) c.ke_render_shader_binding {
            return .{ .name = name, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = 0 };
        }
    };
}

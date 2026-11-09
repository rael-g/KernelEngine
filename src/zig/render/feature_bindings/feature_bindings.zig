//! The bindings a lit pass gives the lighting features its shader declares outside any block: the
//! directional shadow, the environment and the clustered lights, from the ids their passes
//! published on the render service.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render = @import("abi_render");

const Clusters = abi_render.c.ke_render_cluster_resources;

/// The cluster pass's buffers in the order it publishes them, beside the name of the shader
/// parameter each one is bound to.
pub const cluster_buffers = [_]struct { field: []const u8, label: [*:0]const u8, parameter: [*:0]const u8 }{
    .{ .field = "point_lights", .label = "clusters.point_lights", .parameter = "point_lights" },
    .{ .field = "spot_lights", .label = "clusters.spot_lights", .parameter = "spot_lights" },
    .{ .field = "point_indices", .label = "clusters.point_indices", .parameter = "point_indices" },
    .{ .field = "point_counts", .label = "clusters.point_counts", .parameter = "point_counts" },
    .{ .field = "spot_indices", .label = "clusters.spot_indices", .parameter = "spot_indices" },
    .{ .field = "spot_counts", .label = "clusters.spot_counts", .parameter = "spot_counts" },
    .{ .field = "grid", .label = "clusters.grid", .parameter = "cluster" },
};

/// The id of the cluster buffer `index` of `cluster_buffers` in `clusters`.
pub fn clusterBuffer(clusters: *Clusters, comptime index: usize) *abi_asset_resolver.c.ke_component_id {
    return &@field(clusters, cluster_buffers[index].field);
}

pub const count = 3 + cluster_buffers.len;

/// Fills `out` with every feature binding, from the ids the shadow and cluster passes published.
/// An absent id binds the neutral value: the white texture for the shadow map and no buffer
/// otherwise. `environment` is the view the environment is sampled from.
pub fn fill(core: *abi_render.c.ke_render_service, environment: abi_asset_resolver.c.ke_gpu_texture_view, shadow: abi_render.c.ke_render_shadow_resources, clusters: Clusters, out: *[count]abi_render_gpu.c.ke_render_shader_binding) void {
    const white_view = core.*.texture_view.?(core, core.*.white_texture.?(core));
    const shadow_raw = core.*.resource_view.?(core, shadow.map);
    out[0] = binding("shadowParams");
    out[0].buffer = core.*.resource_buffer.?(core, shadow.light);
    out[0].buffer_size = core.*.resource_buffer_size.?(core, shadow.light);
    out[1] = binding("shadowMap");
    out[1].texture_view = if (shadow_raw != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) shadow_raw else white_view;
    out[2] = binding("ibl_env");
    out[2].texture_view = environment;
    var c = clusters;
    inline for (cluster_buffers, 0..) |cb, i| {
        const id = clusterBuffer(&c, i).*;
        out[3 + i] = binding(cb.parameter);
        out[3 + i].buffer = core.*.resource_buffer.?(core, id);
        out[3 + i].buffer_size = core.*.resource_buffer_size.?(core, id);
    }
}

fn binding(name: [*:0]const u8) abi_render_gpu.c.ke_render_shader_binding {
    return .{ .name = name, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = 0 };
}

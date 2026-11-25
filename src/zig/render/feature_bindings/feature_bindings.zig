//! The bindings a lit pass gives the lighting features its shader declares outside any block: the
//! directional shadow, the environment and the clustered lights, from the resources their passes
//! published in the frame.

const abi_render_gpu = @import("abi_render_gpu");
const abi_render = @import("abi_render");
const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");

const rg = abi_render_graph.c;
const names = abi_render.c;

/// The cluster pass's buffers in the order it publishes them: the name each is published under and
/// the shader parameter it is bound to.
pub const cluster_buffers = [_]struct { name: [*:0]const u8, parameter: [*:0]const u8 }{
    .{ .name = names.KE_RENDER_RESOURCE_CLUSTER_POINT_LIGHTS, .parameter = "point_lights" },
    .{ .name = names.KE_RENDER_RESOURCE_CLUSTER_SPOT_LIGHTS, .parameter = "spot_lights" },
    .{ .name = names.KE_RENDER_RESOURCE_CLUSTER_POINT_INDICES, .parameter = "point_indices" },
    .{ .name = names.KE_RENDER_RESOURCE_CLUSTER_POINT_COUNTS, .parameter = "point_counts" },
    .{ .name = names.KE_RENDER_RESOURCE_CLUSTER_SPOT_INDICES, .parameter = "spot_indices" },
    .{ .name = names.KE_RENDER_RESOURCE_CLUSTER_SPOT_COUNTS, .parameter = "spot_counts" },
    .{ .name = names.KE_RENDER_RESOURCE_CLUSTER_GRID, .parameter = "cluster" },
};

pub const count = 3 + cluster_buffers.len;

/// What the shadow and cluster passes published in the frame being declared; an invalid resource is
/// one no pass published.
pub const Published = struct {
    shadow_map: rg.ke_render_graph_resource,
    shadow_light: rg.ke_render_graph_resource,
    clusters: [cluster_buffers.len]rg.ke_render_graph_resource,
};

/// The resources published in `frame` under the names of the shadow and the clusters.
pub fn find(frame: *abi_render_frame.c.ke_render_frame) Published {
    var p: Published = undefined;
    p.shadow_map = frame.find.?(frame, names.KE_RENDER_RESOURCE_SHADOW_MAP);
    p.shadow_light = frame.find.?(frame, names.KE_RENDER_RESOURCE_SHADOW_LIGHT);
    inline for (cluster_buffers, 0..) |cb, i| p.clusters[i] = frame.find.?(frame, cb.name);
    return p;
}

/// Writes into `out` a use of every published resource, read by a lit pass, and returns how many.
pub fn uses(p: Published, out: *[count]rg.ke_render_graph_use) u32 {
    var n: u32 = 0;
    const all = [_]struct { r: rg.ke_render_graph_resource, usage: rg.ke_render_graph_usage }{
        .{ .r = p.shadow_map, .usage = rg.KE_RENDER_GRAPH_USAGE_SAMPLED },
        .{ .r = p.shadow_light, .usage = rg.KE_RENDER_GRAPH_USAGE_UNIFORM },
    };
    for (all) |a| if (a.r != rg.KE_RENDER_GRAPH_RESOURCE_INVALID) {
        out[n] = useOf(a.r, a.usage);
        n += 1;
    };
    for (p.clusters) |r| if (r != rg.KE_RENDER_GRAPH_RESOURCE_INVALID) {
        out[n] = useOf(r, rg.KE_RENDER_GRAPH_USAGE_STORAGE_READ);
        n += 1;
    };
    return n;
}

fn useOf(r: rg.ke_render_graph_resource, usage: rg.ke_render_graph_usage) rg.ke_render_graph_use {
    var u = @import("std").mem.zeroes(rg.ke_render_graph_use);
    u.resource = r;
    u.usage = usage;
    return u;
}

/// Fills `out` with every feature binding, from what `ctx` holds behind the published resources. An
/// absent resource binds the neutral value: the white texture for the shadow map and no buffer
/// otherwise. `environment` is the view the environment is sampled from.
pub fn fill(core: *abi_render.c.ke_render_service, ctx: *rg.ke_render_graph_ctx, environment: abi_render.c.ke_gpu_texture_view, p: Published, out: *[count]abi_render_gpu.c.ke_render_shader_binding) void {
    const white_view = core.*.texture_view.?(core, core.*.white_texture.?(core));
    out[0] = binding("shadowParams");
    out[0].buffer = ctx.buffer.?(ctx, p.shadow_light);
    out[0].buffer_size = ctx.buffer_size.?(ctx, p.shadow_light);
    out[1] = binding("shadowMap");
    out[1].texture_view = if (p.shadow_map != rg.KE_RENDER_GRAPH_RESOURCE_INVALID) ctx.texture_view.?(ctx, p.shadow_map) else white_view;
    out[2] = binding("ibl_env");
    out[2].texture_view = environment;
    inline for (cluster_buffers, 0..) |cb, i| {
        out[3 + i] = binding(cb.parameter);
        out[3 + i].buffer = ctx.buffer.?(ctx, p.clusters[i]);
        out[3 + i].buffer_size = ctx.buffer_size.?(ctx, p.clusters[i]);
    }
}

fn binding(name: [*:0]const u8) abi_render_gpu.c.ke_render_shader_binding {
    return .{ .name = name, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = 0 };
}

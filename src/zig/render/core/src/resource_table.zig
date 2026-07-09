const rc = @import("render_core.zig");
const c = rc.c;

// Named-resource table: declare()/import_texture() register a resource under
// a tag-cid (the runtime access-list identity passes order by), cid()/
// resource_view() resolve it back. This is the render-graph-via-ECS-tags
// mechanism: no render-graph object, just resources registered by name.

pub fn declare(self: [*c]c.ke_render_core, desc: [*c]const c.ke_render_resource_desc, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    _ = out_error;
    const st = rc.coreOf(self);
    if (st.resource_count >= rc.MAX_RESOURCES) return c.KE_COMPONENT_INVALID;

    const cid = st.ecs.component_register.?(st.ecs, desc.*.name, 0);

    var w = desc.*.width;
    var h = desc.*.height;
    if (desc.*.size_mode == c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER) {
        w = @intFromFloat(@as(f32, @floatFromInt(st.backbuffer_w)) * desc.*.scale_x);
        h = @intFromFloat(@as(f32, @floatFromInt(st.backbuffer_h)) * desc.*.scale_y);
    }

    const depth = rc.isDepthFormat(desc.*.format);
    // Depth targets are sampleable too (deferred-lighting reads the G-buffer
    // depth to reconstruct position). WGPU allows RenderAttachment|TextureBinding
    // on Depth32Float; the pass that writes it and the later pass that samples it
    // don't overlap, so no in-pass read/write hazard.
    const usage: c.ke_gpu_texture_usage = if (depth)
        c.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH | c.KE_GPU_TEXTURE_USAGE_SAMPLED
    else
        c.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH | c.KE_GPU_TEXTURE_USAGE_SAMPLED;

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .width = w,
        .height = h,
        .depth_or_array_layers = 1,
        .format = desc.*.format,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .usage = usage,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = null,
        .initial_data_size = 0,
    });

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .format = desc.*.format,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .aspect = if (depth) c.KE_GPU_TEXTURE_ASPECT_DEPTH else c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    });

    st.resources[st.resource_count] = .{
        .name = desc.*.name,
        .cid = cid,
        .format = desc.*.format,
        .texture = tex,
        .view = view,
        .is_backbuffer = false,
        .is_transient = true,
        .clear_value = desc.*.clear_value,
    };
    st.resource_count += 1;
    return cid;
}

pub fn importTexture(self: [*c]c.ke_render_core, name: [*c]const u8, tex: c.ke_gpu_texture, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    _ = out_error;
    const st = rc.coreOf(self);
    if (st.resource_count >= rc.MAX_RESOURCES) return c.KE_COMPONENT_INVALID;
    const cid = st.ecs.component_register.?(st.ecs, name, 0);
    st.resources[st.resource_count] = .{
        .name = name,
        .cid = cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
        .texture = tex,
        .view = c.KE_GPU_INVALID_HANDLE, // view creation needs a format — refinement
        .is_backbuffer = false,
        .is_transient = false,
        .clear_value = .{ 0, 0, 0, 0 },
    };
    st.resource_count += 1;
    return cid;
}

pub fn cidOf(self: [*c]c.ke_render_core, name: [*c]const u8) callconv(.c) c.ke_component_id {
    const st = rc.coreOf(self);
    if (st.find(name)) |r| return r.cid;
    return c.KE_COMPONENT_INVALID;
}

pub fn resourceView(self: [*c]c.ke_render_core, name: [*c]const u8) callconv(.c) c.ke_gpu_texture_view {
    const r = rc.coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.view;
}

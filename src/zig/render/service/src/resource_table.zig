const rc = @import("render_service.zig");
const c = rc.c;

// Named-resource table: declare()/import_texture() register a resource under
// a tag-cid (the runtime access-list identity passes order by), cid()/
// resource_view() resolve it back. This is the render-graph-via-ECS-tags
// mechanism: no render-graph object, just resources registered by name.

pub fn declare(self: [*c]c.ke_render_service, desc: [*c]const c.ke_render_resource_desc, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
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
    // don't overlap, so no in-pass read/write hazard. COPY_SRC|COPY_DST let any
    // declared resource be a copy_texture_to_texture endpoint (e.g. "hdr" snapshotted
    // into "hdr_opaque" for the transparent-forward pass's refraction read) without
    // a per-resource opt-in — the same blanket-permissive approach as SAMPLED above.
    const usage: c.ke_gpu_texture_usage = if (depth)
        c.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH | c.KE_GPU_TEXTURE_USAGE_SAMPLED |
            c.KE_GPU_TEXTURE_USAGE_COPY_SRC | c.KE_GPU_TEXTURE_USAGE_COPY_DST
    else
        c.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH | c.KE_GPU_TEXTURE_USAGE_SAMPLED |
            c.KE_GPU_TEXTURE_USAGE_COPY_SRC | c.KE_GPU_TEXTURE_USAGE_COPY_DST;

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

pub fn importTexture(self: [*c]c.ke_render_service, name: [*c]const u8, tex: c.ke_gpu_texture, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
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

// Mints a tag cid under `name` with no GPU payload — for a producer/consumer
// ordering dependency that isn't itself a texture/buffer/bind-group (e.g.
// cluster's cull compute WRITEs "light_clusters" purely so the scheduler
// orders deferred/forward's READ after it; the actual light data crosses via
// import_bind_group's "cluster_lights", a separate name). Same table, same
// cid() lookup as every other named resource — just no backing resource.
pub fn importTag(self: [*c]c.ke_render_service, name: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    _ = out_error;
    const st = rc.coreOf(self);
    if (st.resource_count >= rc.MAX_RESOURCES) return c.KE_COMPONENT_INVALID;
    const cid = st.ecs.component_register.?(st.ecs, name, 0);
    st.resources[st.resource_count] = .{
        .name = name,
        .cid = cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
        .texture = c.KE_GPU_INVALID_HANDLE,
        .view = c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = false,
        .is_transient = false,
        .clear_value = .{ 0, 0, 0, 0 },
    };
    st.resource_count += 1;
    return cid;
}

// Publishes a producer-owned GPU buffer under `name` (e.g. shadow's LVP uniform).
// Mirrors importTexture: the resource is non-transient (the producer, not the
// table, owns and destroys it) and carries no texture/view.
pub fn importBuffer(self: [*c]c.ke_render_service, name: [*c]const u8, buffer: c.ke_gpu_buffer, size: u64, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    _ = out_error;
    const st = rc.coreOf(self);
    if (st.resource_count >= rc.MAX_RESOURCES) return c.KE_COMPONENT_INVALID;
    const cid = st.ecs.component_register.?(st.ecs, name, 0);
    st.resources[st.resource_count] = .{
        .name = name,
        .cid = cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
        .texture = c.KE_GPU_INVALID_HANDLE,
        .view = c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = false,
        .is_transient = false,
        .clear_value = .{ 0, 0, 0, 0 },
        .buffer = buffer,
        .buffer_size = size,
    };
    st.resource_count += 1;
    return cid;
}

// Publishes a producer-owned GPU bind group (+ the layout it was built from)
// under `name` (e.g. cluster's light-list set-3 bind group). A consumer
// building its own pipeline needs the layout at setup time, not just the bind
// group instance at draw time.
pub fn importBindGroup(self: [*c]c.ke_render_service, name: [*c]const u8, bg: c.ke_gpu_bind_group,
                       layout: c.ke_gpu_bind_group_layout, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    _ = out_error;
    const st = rc.coreOf(self);
    if (st.resource_count >= rc.MAX_RESOURCES) return c.KE_COMPONENT_INVALID;
    const cid = st.ecs.component_register.?(st.ecs, name, 0);
    st.resources[st.resource_count] = .{
        .name = name,
        .cid = cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
        .texture = c.KE_GPU_INVALID_HANDLE,
        .view = c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = false,
        .is_transient = false,
        .clear_value = .{ 0, 0, 0, 0 },
        .bind_group = bg,
        .bind_group_layout = layout,
    };
    st.resource_count += 1;
    return cid;
}

pub fn cidOf(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_component_id {
    const st = rc.coreOf(self);
    if (st.find(name)) |r| return r.cid;
    return c.KE_COMPONENT_INVALID;
}

pub fn resourceView(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_gpu_texture_view {
    const r = rc.coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.view;
}

pub fn resourceTexture(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_gpu_texture {
    const r = rc.coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.texture;
}

// KE_GPU_INVALID_HANDLE if no buffer with that name was published (importBuffer).
pub fn resourceBuffer(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_gpu_buffer {
    const r = rc.coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.buffer;
}

// 0 if no buffer with that name was published.
pub fn resourceBufferSize(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) u64 {
    const r = rc.coreOf(self).find(name) orelse return 0;
    return r.buffer_size;
}

// KE_GPU_INVALID_HANDLE if no bind group with that name was published (importBindGroup).
pub fn resourceBindGroup(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_gpu_bind_group {
    const r = rc.coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.bind_group;
}

// The layout the named bind group was built from (for a consumer's own pipeline
// creation). KE_GPU_INVALID_HANDLE if no bind group with that name was published.
pub fn resourceBindGroupLayout(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_gpu_bind_group_layout {
    const r = rc.coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.bind_group_layout;
}

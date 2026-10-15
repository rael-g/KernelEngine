//! The table of named resources a pass can refer to, and the lookups on it.

const rc = @import("render_service.zig");
const c = rc.c;

/// Every adder registers the name as a component with the service's ecs and appends one entry
/// to the table in call order. None fills its error out-parameter. Declares a texture resource:
/// registers the name, creates a texture and its view on the device,
/// and appends a transient entry that records the format and the clear value. A depth format gets
/// a depth attachment, any other a color attachment. A size relative to the backbuffer is scaled
/// from the size the service last read from the target. Entries made here are the only
/// transient ones: `destroyCore` destroys the texture and view of transient entries and of no
/// other entry. Returns the invalid component id, with an out-of-memory error, when the table
/// cannot grow; a texture the device fails to create is not detected.
pub fn declare(self: [*c]c.ke_render_service, desc: [*c]const c.ke_render_resource_desc, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    const st = rc.coreOf(self);
    st.resources.ensureUnusedCapacity(rc.gpa, 1) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "resource table allocation failed", @src().file, @intCast(@src().line), null);
        return c.KE_COMPONENT_INVALID;
    };

    const cid = st.ecs.component_register.?(st.ecs, desc.*.name, 0, null, 0, null);

    var w = desc.*.width;
    var h = desc.*.height;
    if (desc.*.size_mode == c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER) {
        w = scaled(st.backbuffer_w, desc.*.scale_x);
        h = scaled(st.backbuffer_h, desc.*.scale_y);
    }

    const made = createTarget(st, desc.*.name, desc.*.format, w, h);
    st.resources.appendAssumeCapacity(.{
        .name = desc.*.name,
        .cid = cid,
        .format = desc.*.format,
        .texture = made.texture,
        .view = made.view,
        .is_backbuffer = false,
        .is_transient = true,
        .clear_value = desc.*.clear_value,
        .relative = desc.*.size_mode == c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .scale_x = desc.*.scale_x,
        .scale_y = desc.*.scale_y,
    });
    return cid;
}

const Target = struct { texture: c.ke_gpu_texture, view: c.ke_gpu_texture_view };

/// Creates a declared target's texture and its view. A depth format gets a depth attachment, any
/// other a color attachment.
fn createTarget(st: *rc.CoreState, name: [*c]const u8, format: c.ke_gpu_texture_format, w: u32, h: u32) Target {
    const depth = rc.isDepthFormat(format);
    const usage: c.ke_gpu_texture_usage = if (depth)
        c.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH | c.KE_GPU_TEXTURE_USAGE_SAMPLED |
            c.KE_GPU_TEXTURE_USAGE_COPY_SRC | c.KE_GPU_TEXTURE_USAGE_COPY_DST
    else
        c.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH | c.KE_GPU_TEXTURE_USAGE_SAMPLED |
            c.KE_GPU_TEXTURE_USAGE_COPY_SRC | c.KE_GPU_TEXTURE_USAGE_COPY_DST;

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .label = name,
        .width = w,
        .height = h,
        .depth_or_array_layers = 1,
        .format = format,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .usage = usage,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = null,
        .initial_data_size = 0,
    });

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .label = name,
        .format = format,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .aspect = if (depth) c.KE_GPU_TEXTURE_ASPECT_DEPTH else c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    });
    return .{ .texture = tex, .view = view };
}

fn scaled(size: u32, scale: f32) u32 {
    return @intFromFloat(@as(f32, @floatFromInt(size)) * scale);
}

/// Recreates the texture and view of every target declared relative to the backbuffer when the
/// backbuffer is no longer the size they were made for, and counts the change in
/// `resource_generation`. The component ids stay; the old views are destroyed, so a pass that kept
/// one rebuilds what it made from it.
pub fn resizeRelative(st: *rc.CoreState) void {
    if (st.backbuffer_w == st.sized_w and st.backbuffer_h == st.sized_h) return;
    if (st.backbuffer_w == 0 or st.backbuffer_h == 0) return;
    for (st.resources.items) |*r| {
        if (!r.relative) continue;
        if (r.view != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture_view.?(st.device, r.view);
        if (r.texture != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture.?(st.device, r.texture);
        const made = createTarget(st, r.name, r.format, scaled(st.backbuffer_w, r.scale_x), scaled(st.backbuffer_h, r.scale_y));
        r.texture = made.texture;
        r.view = made.view;
    }
    st.sized_w = st.backbuffer_w;
    st.sized_h = st.backbuffer_h;
    st.resource_generation +%= 1;
}

/// Slot `resource_generation`. Counts the times the declared targets were recreated.
pub fn resourceGeneration(self: [*c]c.ke_render_service) callconv(.c) u32 {
    return rc.coreOf(self).resource_generation;
}

/// Appends an entry for a texture owned by the caller, with no view. Returns the invalid component
/// id when the table cannot grow, with an out-of-memory error.
pub fn importTexture(self: [*c]c.ke_render_service, name: [*c]const u8, tex: c.ke_gpu_texture, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    const st = rc.coreOf(self);
    st.resources.ensureUnusedCapacity(rc.gpa, 1) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "resource table allocation failed", @src().file, @intCast(@src().line), null);
        return c.KE_COMPONENT_INVALID;
    };
    const cid = st.ecs.component_register.?(st.ecs, name, 0, null, 0, null);
    st.resources.appendAssumeCapacity(.{
        .name = name,
        .cid = cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
        .texture = tex,
        .view = c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = false,
        .is_transient = false,
        .clear_value = .{ 0, 0, 0, 0 },
    });
    return cid;
}

/// Appends an entry that names a resource with no handle, so passes can order on it. Returns the
/// invalid component id when the table cannot grow, with an out-of-memory error.
pub fn importTag(self: [*c]c.ke_render_service, name: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    const st = rc.coreOf(self);
    st.resources.ensureUnusedCapacity(rc.gpa, 1) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "resource table allocation failed", @src().file, @intCast(@src().line), null);
        return c.KE_COMPONENT_INVALID;
    };
    const cid = st.ecs.component_register.?(st.ecs, name, 0, null, 0, null);
    st.resources.appendAssumeCapacity(.{
        .name = name,
        .cid = cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
        .texture = c.KE_GPU_INVALID_HANDLE,
        .view = c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = false,
        .is_transient = false,
        .clear_value = .{ 0, 0, 0, 0 },
    });
    return cid;
}

/// Appends an entry for a buffer owned by the caller, recording its size. Returns the invalid
/// component id when the table cannot grow, with an out-of-memory error.
pub fn importBuffer(self: [*c]c.ke_render_service, name: [*c]const u8, buffer: c.ke_gpu_buffer, size: u64, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    const st = rc.coreOf(self);
    st.resources.ensureUnusedCapacity(rc.gpa, 1) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "resource table allocation failed", @src().file, @intCast(@src().line), null);
        return c.KE_COMPONENT_INVALID;
    };
    const cid = st.ecs.component_register.?(st.ecs, name, 0, null, 0, null);
    st.resources.appendAssumeCapacity(.{
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
    });
    return cid;
}

/// Returns the component id of the named entry; the invalid id for an unknown name.
pub fn cidOf(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_component_id {
    const st = rc.coreOf(self);
    if (st.find(name)) |r| return r.cid;
    return c.KE_COMPONENT_INVALID;
}

/// Returns the view of the named entry; the invalid handle for an unknown name.
pub fn resourceView(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_gpu_texture_view {
    const r = rc.coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.view;
}

/// Returns the texture of the named entry; the invalid handle for an unknown name.
pub fn resourceTexture(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_gpu_texture {
    const r = rc.coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.texture;
}

/// Returns the buffer of the named entry; the invalid handle for an unknown name.
pub fn resourceBuffer(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) c.ke_gpu_buffer {
    const r = rc.coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.buffer;
}

/// Returns the size recorded by `importBuffer`; zero for an unknown name and for an entry that is
/// not a buffer.
pub fn resourceBufferSize(self: [*c]c.ke_render_service, name: [*c]const u8) callconv(.c) u64 {
    const r = rc.coreOf(self).find(name) orelse return 0;
    return r.buffer_size;
}

/// Reports the size read from the target when the service was created. The target is not asked.
pub fn backbufferSize(self: [*c]c.ke_render_service, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const st = rc.coreOf(self);
    if (out_w != null) out_w.* = st.backbuffer_w;
    if (out_h != null) out_h.* = st.backbuffer_h;
}

/// Asks the render target for its format on every call, not the format recorded for the
/// backbuffer entry when the service was created.
pub fn backbufferFormat(self: [*c]c.ke_render_service) callconv(.c) c.ke_gpu_texture_format {
    const st = rc.coreOf(self);
    return st.target.format.?(st.target);
}

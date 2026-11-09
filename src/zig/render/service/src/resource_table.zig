//! The table of named resources a pass can refer to, and the lookups on it.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");
const rc = @import("render_service.zig");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const R = rc.R;
const log = std.log.scoped(.render_service);

/// Every adder registers the name as a component with the service's ecs and appends one entry
/// to the table in call order, writing its cid, and fails as out of memory when the table cannot
/// grow or with the ecs's code when the name cannot be registered. A name already in the table is
/// registered with a numeric suffix, so every call makes a resource of its own. Declares a texture resource:
/// registers the name, creates a texture and its view on the device,
/// and appends a transient entry that records the format and the clear value. A depth format gets
/// a depth attachment, any other a color attachment. A size relative to the backbuffer is scaled
/// from the size the service last read from the target. Entries made here are the only
/// transient ones: `destroyCore` destroys the texture and view of transient entries and of no
/// other entry. A texture or view the device refuses fails with the
/// device's code.
pub fn declare(self: [*c]abi_render.c.ke_render_service, params: [*c]const abi_render.c.ke_render_resource_params, out_cid: [*c]abi_asset_resolver.c.ke_component_id) callconv(.c) abi_result.c.ke_result {
    const out = out_cid orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_COMPONENT_INVALID;
    if (self == null or params == null or params.*.name == null) return R.code(error.InvalidArgument);
    out.* = declareResource(rc.coreOf(self), params.*) catch |err| return R.code(err);
    return R.ok;
}

fn declareResource(st: *rc.CoreState, params: abi_render.c.ke_render_resource_params) R.Error!abi_asset_resolver.c.ke_component_id {
    var w = params.width;
    var h = params.height;
    if (params.size_mode == abi_render.c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER) {
        w = scaled(st.backbuffer_w, params.scale_x);
        h = scaled(st.backbuffer_h, params.scale_y);
    }
    const entry = try register(st, params.name);
    errdefer rc.gpa.free(std.mem.span(entry.name));
    const made = try createTarget(st, params.name, params.format, w, h);
    var r = entry;
    r.format = params.format;
    r.texture = made.texture;
    r.view = made.view;
    r.is_transient = true;
    r.clear_value = .{ params.clear_value.x, params.clear_value.y, params.clear_value.z, params.clear_value.w };
    r.relative = params.size_mode == abi_render.c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER;
    r.scale_x = params.scale_x;
    r.scale_y = params.scale_y;
    st.resources.appendAssumeCapacity(r);
    return r.cid;
}

/// An entry for `name` with no payload, its cid registered and its name owned, once the table has
/// room for it; the caller appends it or frees the name.
fn register(st: *rc.CoreState, name: [*c]const u8) R.Error!rc.Resource {
    try st.resources.ensureUnusedCapacity(rc.gpa, 1);
    const owned = try uniqueName(st, std.mem.span(name));
    errdefer rc.gpa.free(owned);
    var cid: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(st.ecs.component_register.?(st.ecs, &abi_ecs.c.ke_component_params{ .name = owned.ptr, .size = 0, .alignment = 0, .fields = null, .field_count = 0 }, &cid));
    return .{
        .name = owned.ptr,
        .cid = cid,
        .format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID,
        .texture = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
        .view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = false,
        .is_transient = false,
        .clear_value = .{ 0, 0, 0, 0 },
    };
}

fn uniqueName(st: *rc.CoreState, name: []const u8) R.Error![:0]u8 {
    if (st.find(name.ptr) == null) return rc.gpa.dupeZ(u8, name);
    var n: u32 = 2;
    while (true) : (n += 1) {
        const candidate = try std.fmt.allocPrintSentinel(rc.gpa, "{s}#{d}", .{ name, n }, 0);
        if (st.find(candidate.ptr) == null) return candidate;
        rc.gpa.free(candidate);
    }
}

const Target = struct { texture: abi_asset_resolver.c.ke_gpu_texture, view: abi_asset_resolver.c.ke_gpu_texture_view };

/// Creates a declared target's texture and its view. A depth format gets a depth attachment, any
/// other a color attachment. Fails with the device's code when either is refused; a refused view
/// destroys the texture.
fn createTarget(st: *rc.CoreState, name: [*c]const u8, format: abi_render_gpu.c.ke_gpu_texture_format, w: u32, h: u32) R.Error!Target {
    const depth = rc.isDepthFormat(format);
    const usage: abi_asset_resolver.c.ke_gpu_texture_usage = if (depth)
        abi_render_gpu.c.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH | abi_render_gpu.c.KE_GPU_TEXTURE_USAGE_SAMPLED |
            abi_render_gpu.c.KE_GPU_TEXTURE_USAGE_COPY_SRC | abi_render_gpu.c.KE_GPU_TEXTURE_USAGE_COPY_DST
    else
        abi_render_gpu.c.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH | abi_render_gpu.c.KE_GPU_TEXTURE_USAGE_SAMPLED |
            abi_render_gpu.c.KE_GPU_TEXTURE_USAGE_COPY_SRC | abi_render_gpu.c.KE_GPU_TEXTURE_USAGE_COPY_DST;

    var tex: abi_asset_resolver.c.ke_gpu_texture = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_texture.?(st.device, &abi_render_gpu.c.ke_gpu_texture_params{
        .label = name,
        .width = w,
        .height = h,
        .depth_or_array_layers = 1,
        .format = format,
        .dimension = abi_render_gpu.c.KE_GPU_TEXTURE_DIM_2D,
        .usage = usage,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = null,
        .initial_data_size = 0,
    }, &tex));
    errdefer st.device.destroy_texture.?(st.device, tex);

    var view: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_texture_view.?(st.device, tex, &abi_render_gpu.c.ke_gpu_texture_view_params{
        .label = name,
        .format = format,
        .dimension = abi_render_gpu.c.KE_GPU_TEXTURE_DIM_2D,
        .aspect = if (depth) abi_render_gpu.c.KE_GPU_TEXTURE_ASPECT_DEPTH else abi_render_gpu.c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    }, &view));
    return .{ .texture = tex, .view = view };
}

fn scaled(size: u32, scale: f32) u32 {
    return @intFromFloat(@as(f32, @floatFromInt(size)) * scale);
}

/// Recreates the texture and view of every target declared relative to the backbuffer when the
/// backbuffer is no longer the size they were made for, and counts the change in
/// `resource_generation`. The component ids stay; the old views are destroyed, so a pass that kept
/// one rebuilds what it made from it. A target the device refuses is left with no texture and no
/// view.
pub fn resizeRelative(st: *rc.CoreState) void {
    if (st.backbuffer_w == st.sized_w and st.backbuffer_h == st.sized_h) return;
    if (st.backbuffer_w == 0 or st.backbuffer_h == 0) return;
    for (st.resources.items) |*r| {
        if (!r.relative) continue;
        if (r.view != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture_view.?(st.device, r.view);
        if (r.texture != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture.?(st.device, r.texture);
        const made = createTarget(st, r.name, r.format, scaled(st.backbuffer_w, r.scale_x), scaled(st.backbuffer_h, r.scale_y)) catch Target{ .texture = abi_render_gpu.c.KE_GPU_INVALID_HANDLE, .view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE };
        r.texture = made.texture;
        r.view = made.view;
    }
    st.sized_w = st.backbuffer_w;
    st.sized_h = st.backbuffer_h;
    st.resource_generation +%= 1;
}

/// Slot `resource_generation`. Counts the times the declared targets were recreated.
pub fn resourceGeneration(self: [*c]abi_render.c.ke_render_service) callconv(.c) u32 {
    return rc.coreOf(self).resource_generation;
}

/// Appends an entry for a texture owned by the caller, with no view.
pub fn importTexture(self: [*c]abi_render.c.ke_render_service, name: [*c]const u8, tex: abi_asset_resolver.c.ke_gpu_texture, out_cid: [*c]abi_asset_resolver.c.ke_component_id) callconv(.c) abi_result.c.ke_result {
    const out = out_cid orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_COMPONENT_INVALID;
    if (self == null or name == null) return R.code(error.InvalidArgument);
    const st = rc.coreOf(self);
    var r = register(st, name) catch |err| return R.code(err);
    r.texture = tex;
    st.resources.appendAssumeCapacity(r);
    out.* = r.cid;
    return R.ok;
}

/// Appends an entry for a resource with no handle, so passes can order on it.
pub fn importTag(self: [*c]abi_render.c.ke_render_service, name: [*c]const u8, out_cid: [*c]abi_asset_resolver.c.ke_component_id) callconv(.c) abi_result.c.ke_result {
    const out = out_cid orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_COMPONENT_INVALID;
    if (self == null or name == null) return R.code(error.InvalidArgument);
    const st = rc.coreOf(self);
    const r = register(st, name) catch |err| return R.code(err);
    st.resources.appendAssumeCapacity(r);
    out.* = r.cid;
    return R.ok;
}

/// Appends an entry for a buffer owned by the caller, recording its size.
pub fn importBuffer(self: [*c]abi_render.c.ke_render_service, name: [*c]const u8, buffer: abi_asset_resolver.c.ke_gpu_buffer, size: u64, out_cid: [*c]abi_asset_resolver.c.ke_component_id) callconv(.c) abi_result.c.ke_result {
    const out = out_cid orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_COMPONENT_INVALID;
    if (self == null or name == null) return R.code(error.InvalidArgument);
    const st = rc.coreOf(self);
    var r = register(st, name) catch |err| return R.code(err);
    r.buffer = buffer;
    r.buffer_size = size;
    st.resources.appendAssumeCapacity(r);
    out.* = r.cid;
    return R.ok;
}

/// Slot `frame_color`. The tag the service imported for the frame's color when it was created.
pub fn frameColor(self: [*c]abi_render.c.ke_render_service) callconv(.c) abi_asset_resolver.c.ke_component_id {
    return rc.coreOf(self).frame_color;
}

/// Slot `frame_depth`. The target the service declared for the frame's depth when it was created.
pub fn frameDepth(self: [*c]abi_render.c.ke_render_service) callconv(.c) abi_asset_resolver.c.ke_component_id {
    return rc.coreOf(self).frame_depth;
}

/// Returns the view of the entry; the invalid handle for an unknown id.
pub fn resourceView(self: [*c]abi_render.c.ke_render_service, resource: abi_asset_resolver.c.ke_component_id) callconv(.c) abi_asset_resolver.c.ke_gpu_texture_view {
    const r = rc.coreOf(self).findId(resource) orelse return abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    return r.view;
}

/// Returns the texture of the entry; the invalid handle for an unknown id.
pub fn resourceTexture(self: [*c]abi_render.c.ke_render_service, resource: abi_asset_resolver.c.ke_component_id) callconv(.c) abi_asset_resolver.c.ke_gpu_texture {
    const r = rc.coreOf(self).findId(resource) orelse return abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    return r.texture;
}

/// Returns the buffer of the entry; the invalid handle for an unknown id.
pub fn resourceBuffer(self: [*c]abi_render.c.ke_render_service, resource: abi_asset_resolver.c.ke_component_id) callconv(.c) abi_asset_resolver.c.ke_gpu_buffer {
    const r = rc.coreOf(self).findId(resource) orelse return abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    return r.buffer;
}

/// Returns the size recorded by `importBuffer`; zero for an unknown id and for an entry that is
/// not a buffer.
pub fn resourceBufferSize(self: [*c]abi_render.c.ke_render_service, resource: abi_asset_resolver.c.ke_component_id) callconv(.c) u64 {
    const r = rc.coreOf(self).findId(resource) orelse return 0;
    return r.buffer_size;
}

/// Reports the size read from the target when the service was created. The target is not asked.
pub fn backbufferSize(self: [*c]abi_render.c.ke_render_service, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const st = rc.coreOf(self);
    if (out_w != null) out_w.* = st.backbuffer_w;
    if (out_h != null) out_h.* = st.backbuffer_h;
}

/// Asks the render target for its format on every call, not the format recorded for the
/// backbuffer entry when the service was created.
/// Returns the format of the entry; the invalid format for an unknown id.
pub fn resourceFormat(self: [*c]abi_render.c.ke_render_service, resource: abi_asset_resolver.c.ke_component_id) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
    const st = rc.coreOf(self);
    if (st.findId(resource)) |r| return r.format;
    return abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID;
}

pub fn backbufferFormat(self: [*c]abi_render.c.ke_render_service) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
    const st = rc.coreOf(self);
    return st.target.format.?(st.target);
}

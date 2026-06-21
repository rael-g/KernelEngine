const std = @import("std");
const wgpu = @cImport(@cInclude("webgpu.h"));
const ke = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/render/gpu_device.h");
});

// ── Internal error set ─────────────────────────────────────────────────────

const GpuError = error{
    OutOfMemory,
    NoAdapter,
    DeviceCreationFailed,
    NotImplemented,
};

// ── State ──────────────────────────────────────────────────────────────────

const DeviceState = struct {
    instance: wgpu.WGPUInstance,
    adapter: wgpu.WGPUAdapter,
    device: wgpu.WGPUDevice,
    queue: wgpu.WGPUQueue,
};

fn state(dev: *ke.ke_gpu_device) *DeviceState {
    return @ptrCast(@alignCast(dev.handle));
}

// ── ke_error translation helpers ───────────────────────────────────────────
//
// All internal code uses Zig's error union (!T).
// These helpers translate at the ABI seam only.

fn setError(
    out_error: ?*?*ke.ke_error,
    err: GpuError,
    msg: [*c]const u8,
    src: std.builtin.SourceLocation,
) void {
    const code: c_int = switch (err) {
        GpuError.OutOfMemory => ke.KE_ERROR_OUT_OF_MEMORY,
        GpuError.NoAdapter, GpuError.DeviceCreationFailed => ke.KE_ERROR_INVALID_OPERATION,
        GpuError.NotImplemented => ke.KE_ERROR_NOT_IMPLEMENTED,
    };
    ke.ke_error_set(out_error, code, msg, src.file, @intCast(src.line));
}

// ── Factory (internal) ────────────────────────────────────────────────────

const gpa = std.heap.c_allocator;

fn createDeviceState() GpuError!*DeviceState {
    const s = gpa.create(DeviceState) catch return GpuError.OutOfMemory;
    errdefer gpa.destroy(s);

    const instance_desc = wgpu.WGPUInstanceDescriptor{ .nextInChain = null };
    s.instance = wgpu.wgpuCreateInstance(&instance_desc) orelse
        return GpuError.DeviceCreationFailed;
    errdefer wgpu.wgpuInstanceRelease(s.instance);

    const adapter_opts = wgpu.WGPURequestAdapterOptions{
        .nextInChain = null,
        .powerPreference = wgpu.WGPUPowerPreference_HighPerformance,
        .backendType = wgpu.WGPUBackendType_Undefined,
        .forceFallbackAdapter = 0,
        .compatibleSurface = null,
    };
    var adapter: wgpu.WGPUAdapter = null;
    wgpu.wgpuInstanceRequestAdapter(s.instance, &adapter_opts, adapterCallback, @ptrCast(&adapter));
    s.adapter = adapter orelse return GpuError.NoAdapter;
    errdefer wgpu.wgpuAdapterRelease(s.adapter);

    var wgpu_device: wgpu.WGPUDevice = null;
    wgpu.wgpuAdapterRequestDevice(s.adapter, null, deviceCallback, @ptrCast(&wgpu_device));
    s.device = wgpu_device orelse return GpuError.DeviceCreationFailed;
    errdefer wgpu.wgpuDeviceRelease(s.device);

    s.queue = wgpu.wgpuDeviceGetQueue(s.device);
    return s;
}

fn createDeviceVtable(s: *DeviceState) GpuError!*ke.ke_gpu_device {
    const dev = gpa.create(ke.ke_gpu_device) catch return GpuError.OutOfMemory;
    dev.* = .{
        .handle = s,
        .get_default_queue = getDefaultQueue,
        .queue_submit = queueSubmit,
        .queue_present = queuePresent,
        .queue_wait_idle = queueWaitIdle,
        .create_fence = createFence,
        .queue_signal_fence = queueSignalFence,
        .wait_fence = waitFence,
        .get_fence_value = getFenceValue,
        .destroy_fence = destroyFence,
        .create_buffer = createBuffer,
        .create_texture = createTexture,
        .create_texture_view = createTextureView,
        .create_sampler = createSampler,
        .create_shader_module = createShaderModule,
        .create_render_pipeline = createRenderPipeline,
        .create_compute_pipeline = createComputePipeline,
        .create_bind_group_layout = createBindGroupLayout,
        .create_bind_group = createBindGroup,
        .destroy_buffer = destroyBuffer,
        .destroy_texture = destroyTexture,
        .destroy_texture_view = destroyTextureView,
        .destroy_sampler = destroySampler,
        .destroy_shader_module = destroyShaderModule,
        .destroy_pipeline = destroyPipeline,
        .destroy_bind_group_layout = destroyBindGroupLayout,
        .destroy_bind_group = destroyBindGroup,
        .encoder_create = encoderCreate,
        .encoder_begin_render_pass = encoderBeginRenderPass,
        .encoder_begin_compute_pass = encoderBeginComputePass,
        .encoder_pipeline_barrier = encoderPipelineBarrier,
        .encoder_copy_buffer_to_buffer = encoderCopyBufferToBuffer,
        .encoder_copy_buffer_to_texture = encoderCopyBufferToTexture,
        .encoder_finish = encoderFinish,
        .encoder_destroy = encoderDestroy,
        .rp_set_pipeline = rpSetPipeline,
        .rp_set_bind_group = rpSetBindGroup,
        .rp_set_vertex_buffer = rpSetVertexBuffer,
        .rp_set_index_buffer = rpSetIndexBuffer,
        .rp_set_viewport = rpSetViewport,
        .rp_set_scissor = rpSetScissor,
        .rp_draw = rpDraw,
        .rp_draw_indexed = rpDrawIndexed,
        .rp_draw_indirect = rpDrawIndirect,
        .rp_end = rpEnd,
        .cp_set_pipeline = cpSetPipeline,
        .cp_set_bind_group = cpSetBindGroup,
        .cp_dispatch = cpDispatch,
        .cp_dispatch_indirect = cpDispatchIndirect,
        .cp_end = cpEnd,
        .cmd_buffer_destroy = cmdBufferDestroy,
        .map_buffer = mapBuffer,
        .map_buffer_write = mapBufferWrite,
        .unmap_buffer = unmapBuffer,
        .get_capabilities = getCapabilities,
        .query_extension = queryExtension,
    };
    return dev;
}

// ── ABI boundary — factory ─────────────────────────────────────────────────

export fn ke_gpu_device_webgpu_create(
    params: ?*const ke.ke_gpu_device_webgpu_params,
    out_error: ?*?*ke.ke_error,
) ke.ke_gpu_device_handle {
    _ = params;

    const s = createDeviceState() catch |err| {
        setError(out_error, err, "webgpu: device initialisation failed", @src());
        return .{ .ref = null, .destroy = null };
    };
    errdefer {
        wgpu.wgpuQueueRelease(s.queue);
        wgpu.wgpuDeviceRelease(s.device);
        wgpu.wgpuAdapterRelease(s.adapter);
        wgpu.wgpuInstanceRelease(s.instance);
        gpa.destroy(s);
    }

    const dev = createDeviceVtable(s) catch |err| {
        setError(out_error, err, "webgpu: vtable allocation failed", @src());
        return .{ .ref = null, .destroy = null };
    };

    return .{ .ref = dev, .destroy = deviceDestroy };
}

// ── Destroy ────────────────────────────────────────────────────────────────

fn deviceDestroy(dev: *ke.ke_gpu_device) callconv(.C) void {
    const s = state(dev);
    wgpu.wgpuQueueRelease(s.queue);
    wgpu.wgpuDeviceRelease(s.device);
    wgpu.wgpuAdapterRelease(s.adapter);
    wgpu.wgpuInstanceRelease(s.instance);
    gpa.destroy(s);
    gpa.destroy(dev);
}

// ── wgpu-native sync callbacks ─────────────────────────────────────────────

fn adapterCallback(
    _: wgpu.WGPURequestAdapterStatus,
    adapter: wgpu.WGPUAdapter,
    _: [*c]const u8,
    userdata: ?*anyopaque,
) callconv(.C) void {
    const out: *wgpu.WGPUAdapter = @ptrCast(@alignCast(userdata));
    out.* = adapter;
}

fn deviceCallback(
    _: wgpu.WGPURequestDeviceStatus,
    device: wgpu.WGPUDevice,
    _: [*c]const u8,
    userdata: ?*anyopaque,
) callconv(.C) void {
    const out: *wgpu.WGPUDevice = @ptrCast(@alignCast(userdata));
    out.* = device;
}

// ── Queue ──────────────────────────────────────────────────────────────────

fn getDefaultQueue(dev: *ke.ke_gpu_device) callconv(.C) ke.ke_gpu_queue {
    return @intFromPtr(state(dev).queue);
}

fn queueSubmit(
    dev: *ke.ke_gpu_device,
    _: ke.ke_gpu_queue,
    _: [*c]?*ke.ke_gpu_command_buffer,
    _: u32,
) callconv(.C) void {
    _ = dev;
    // TODO(R3): translate ke_gpu_command_buffer* array → WGPUCommandBuffer array
}

fn queuePresent(dev: *ke.ke_gpu_device, _: ke.ke_gpu_queue) callconv(.C) void {
    _ = dev;
    // TODO(R3): wgpuSurfacePresent
}

fn queueWaitIdle(dev: *ke.ke_gpu_device, q: ke.ke_gpu_queue) callconv(.C) void {
    _ = dev;
    wgpu.wgpuQueueOnSubmittedWorkDone(@ptrFromInt(q), 0, null, null);
    // TODO(R3): proper poll-until-idle via wgpuDevicePoll
}

// ── Fence (timeline) ───────────────────────────────────────────────────────
//
// wgpu-native does not expose timeline semaphores via the core WebGPU API.
// These stubs return error / sentinel until R3 adds the wgpu-native extension.

fn createFence(_: *ke.ke_gpu_device, _: u64) callconv(.C) ke.ke_gpu_fence {
    return ke.KE_GPU_INVALID_HANDLE;
}

fn queueSignalFence(_: *ke.ke_gpu_device, _: ke.ke_gpu_queue, _: ke.ke_gpu_fence, _: u64) callconv(.C) void {}

fn waitFence(
    _: *ke.ke_gpu_device,
    _: ke.ke_gpu_fence,
    _: u64,
    _: u64,
    out_error: ?*?*ke.ke_error,
) callconv(.C) bool {
    setError(out_error, GpuError.NotImplemented, "webgpu: timeline fences not yet implemented", @src());
    return false;
}

fn getFenceValue(_: *ke.ke_gpu_device, _: ke.ke_gpu_fence) callconv(.C) u64 {
    return 0;
}

fn destroyFence(_: *ke.ke_gpu_device, _: ke.ke_gpu_fence) callconv(.C) void {}

// ── Resource creation ──────────────────────────────────────────────────────

fn createBuffer(dev: *ke.ke_gpu_device, p: *const ke.ke_gpu_buffer_params) callconv(.C) ke.ke_gpu_buffer {
    const desc = wgpu.WGPUBufferDescriptor{
        .nextInChain = null,
        .label = null,
        .usage = @intCast(p.usage),
        .size = p.size,
        .mappedAtCreation = if (p.mapped_at_creation != 0) 1 else 0,
    };
    return @intFromPtr(wgpu.wgpuDeviceCreateBuffer(state(dev).device, &desc));
}

fn createTexture(_: *ke.ke_gpu_device, _: *const ke.ke_gpu_texture_params) callconv(.C) ke.ke_gpu_texture {
    return ke.KE_GPU_INVALID_HANDLE; // TODO(R3)
}

fn createTextureView(_: *ke.ke_gpu_device, _: ke.ke_gpu_texture, _: *const ke.ke_gpu_texture_view_params) callconv(.C) ke.ke_gpu_texture_view {
    return ke.KE_GPU_INVALID_HANDLE; // TODO(R3)
}

fn createSampler(_: *ke.ke_gpu_device, _: *const ke.ke_gpu_sampler_params) callconv(.C) ke.ke_gpu_sampler {
    return ke.KE_GPU_INVALID_HANDLE; // TODO(R3)
}

fn createShaderModule(dev: *ke.ke_gpu_device, p: *const ke.ke_gpu_shader_module_params) callconv(.C) ke.ke_gpu_shader_module {
    const spirv = wgpu.WGPUShaderModuleSPIRVDescriptor{
        .chain = .{ .next = null, .sType = wgpu.WGPUSType_ShaderModuleSPIRVDescriptor },
        .codeSize = @intCast(p.byte_size / 4),
        .code = p.code,
    };
    const desc = wgpu.WGPUShaderModuleDescriptor{
        .nextInChain = @ptrCast(&spirv),
        .label = p.entry_point,
    };
    return @intFromPtr(wgpu.wgpuDeviceCreateShaderModule(state(dev).device, &desc));
}

fn createRenderPipeline(_: *ke.ke_gpu_device, _: *const ke.ke_gpu_render_pipeline_params) callconv(.C) ke.ke_gpu_pipeline {
    return ke.KE_GPU_INVALID_HANDLE; // TODO(R3)
}

fn createComputePipeline(_: *ke.ke_gpu_device, _: *const ke.ke_gpu_compute_pipeline_params) callconv(.C) ke.ke_gpu_pipeline {
    return ke.KE_GPU_INVALID_HANDLE; // TODO(R3)
}

fn createBindGroupLayout(_: *ke.ke_gpu_device, _: *const ke.ke_gpu_bind_group_layout_params) callconv(.C) ke.ke_gpu_bind_group_layout {
    return ke.KE_GPU_INVALID_HANDLE; // TODO(R3)
}

fn createBindGroup(_: *ke.ke_gpu_device, _: *const ke.ke_gpu_bind_group_params) callconv(.C) ke.ke_gpu_bind_group {
    return ke.KE_GPU_INVALID_HANDLE; // TODO(R3)
}

// ── Resource destruction ───────────────────────────────────────────────────

fn destroyBuffer(_: *ke.ke_gpu_device, h: ke.ke_gpu_buffer) callconv(.C) void {
    wgpu.wgpuBufferDestroy(@ptrFromInt(h));
    wgpu.wgpuBufferRelease(@ptrFromInt(h));
}

fn destroyTexture(_: *ke.ke_gpu_device, h: ke.ke_gpu_texture) callconv(.C) void {
    wgpu.wgpuTextureDestroy(@ptrFromInt(h));
    wgpu.wgpuTextureRelease(@ptrFromInt(h));
}

fn destroyTextureView(_: *ke.ke_gpu_device, h: ke.ke_gpu_texture_view) callconv(.C) void {
    wgpu.wgpuTextureViewRelease(@ptrFromInt(h));
}

fn destroySampler(_: *ke.ke_gpu_device, h: ke.ke_gpu_sampler) callconv(.C) void {
    wgpu.wgpuSamplerRelease(@ptrFromInt(h));
}

fn destroyShaderModule(_: *ke.ke_gpu_device, h: ke.ke_gpu_shader_module) callconv(.C) void {
    wgpu.wgpuShaderModuleRelease(@ptrFromInt(h));
}

fn destroyPipeline(_: *ke.ke_gpu_device, h: ke.ke_gpu_pipeline) callconv(.C) void {
    wgpu.wgpuRenderPipelineRelease(@ptrFromInt(h));
}

fn destroyBindGroupLayout(_: *ke.ke_gpu_device, h: ke.ke_gpu_bind_group_layout) callconv(.C) void {
    wgpu.wgpuBindGroupLayoutRelease(@ptrFromInt(h));
}

fn destroyBindGroup(_: *ke.ke_gpu_device, h: ke.ke_gpu_bind_group) callconv(.C) void {
    wgpu.wgpuBindGroupRelease(@ptrFromInt(h));
}

// ── Encoder ────────────────────────────────────────────────────────────────

fn encoderCreate(dev: *ke.ke_gpu_device) callconv(.C) ?*anyopaque {
    const desc = wgpu.WGPUCommandEncoderDescriptor{ .nextInChain = null, .label = null };
    return wgpu.wgpuDeviceCreateCommandEncoder(state(dev).device, &desc);
}

fn encoderBeginRenderPass(_: *ke.ke_gpu_device, encoder: ?*anyopaque, _: *const ke.ke_gpu_render_pass_params) callconv(.C) ?*anyopaque {
    _ = encoder;
    return null; // TODO(R3): translate ke_gpu_render_pass_params → WGPURenderPassDescriptor
}

fn encoderBeginComputePass(_: *ke.ke_gpu_device, encoder: ?*anyopaque) callconv(.C) ?*anyopaque {
    const desc = wgpu.WGPUComputePassDescriptor{ .nextInChain = null, .label = null, .timestampWrites = null };
    return wgpu.wgpuCommandEncoderBeginComputePass(@ptrCast(encoder), &desc);
}

fn encoderPipelineBarrier(_: *ke.ke_gpu_device, _: ?*anyopaque, _: *const ke.ke_gpu_barrier) callconv(.C) void {
    // WebGPU barriers are implicit in the resource model; no-op.
}

fn encoderCopyBufferToBuffer(_: *ke.ke_gpu_device, encoder: ?*anyopaque, src: ke.ke_gpu_buffer, src_offset: usize, dst: ke.ke_gpu_buffer, dst_offset: usize, size: usize) callconv(.C) void {
    wgpu.wgpuCommandEncoderCopyBufferToBuffer(@ptrCast(encoder), @ptrFromInt(src), src_offset, @ptrFromInt(dst), dst_offset, size);
}

fn encoderCopyBufferToTexture(_: *ke.ke_gpu_device, _: ?*anyopaque, _: ke.ke_gpu_buffer, _: usize, _: ke.ke_gpu_texture, _: u32, _: u32, _: u32, _: u32, _: u32) callconv(.C) void {
    // TODO(R3): wgpuCommandEncoderCopyBufferToTexture
}

fn encoderFinish(_: *ke.ke_gpu_device, encoder: ?*anyopaque) callconv(.C) ?*anyopaque {
    const desc = wgpu.WGPUCommandBufferDescriptor{ .nextInChain = null, .label = null };
    return wgpu.wgpuCommandEncoderFinish(@ptrCast(encoder), &desc);
}

fn encoderDestroy(_: *ke.ke_gpu_device, encoder: ?*anyopaque) callconv(.C) void {
    wgpu.wgpuCommandEncoderRelease(@ptrCast(encoder));
}

// ── Render pass backing ────────────────────────────────────────────────────

fn rpSetPipeline(_: *ke.ke_gpu_device, rp: ?*anyopaque, pipe: ke.ke_gpu_pipeline) callconv(.C) void {
    wgpu.wgpuRenderPassEncoderSetPipeline(@ptrCast(rp), @ptrFromInt(pipe));
}

fn rpSetBindGroup(_: *ke.ke_gpu_device, rp: ?*anyopaque, group_index: u32, bg: ke.ke_gpu_bind_group, dynamic_offsets: [*c]const u32, dyn_count: u32) callconv(.C) void {
    wgpu.wgpuRenderPassEncoderSetBindGroup(@ptrCast(rp), group_index, @ptrFromInt(bg), dyn_count, dynamic_offsets);
}

fn rpSetVertexBuffer(_: *ke.ke_gpu_device, rp: ?*anyopaque, slot: u32, b: ke.ke_gpu_buffer, offset: usize) callconv(.C) void {
    wgpu.wgpuRenderPassEncoderSetVertexBuffer(@ptrCast(rp), slot, @ptrFromInt(b), offset, wgpu.WGPU_WHOLE_SIZE);
}

fn rpSetIndexBuffer(_: *ke.ke_gpu_device, rp: ?*anyopaque, b: ke.ke_gpu_buffer, fmt: ke.ke_gpu_index_format, offset: usize) callconv(.C) void {
    const wgpu_fmt: wgpu.WGPUIndexFormat = switch (fmt) {
        ke.KE_GPU_INDEX_FORMAT_UINT16 => wgpu.WGPUIndexFormat_Uint16,
        ke.KE_GPU_INDEX_FORMAT_UINT32 => wgpu.WGPUIndexFormat_Uint32,
        else => wgpu.WGPUIndexFormat_Undefined,
    };
    wgpu.wgpuRenderPassEncoderSetIndexBuffer(@ptrCast(rp), @ptrFromInt(b), wgpu_fmt, offset, wgpu.WGPU_WHOLE_SIZE);
}

fn rpSetViewport(_: *ke.ke_gpu_device, rp: ?*anyopaque, x: f32, y: f32, w: f32, h: f32, min_depth: f32, max_depth: f32) callconv(.C) void {
    wgpu.wgpuRenderPassEncoderSetViewport(@ptrCast(rp), x, y, w, h, min_depth, max_depth);
}

fn rpSetScissor(_: *ke.ke_gpu_device, rp: ?*anyopaque, x: i32, y: i32, w: u32, h: u32) callconv(.C) void {
    wgpu.wgpuRenderPassEncoderSetScissorRect(@ptrCast(rp), @intCast(x), @intCast(y), w, h);
}

fn rpDraw(_: *ke.ke_gpu_device, rp: ?*anyopaque, vert_count: u32, inst_count: u32, first_vert: u32, first_inst: u32) callconv(.C) void {
    wgpu.wgpuRenderPassEncoderDraw(@ptrCast(rp), vert_count, inst_count, first_vert, first_inst);
}

fn rpDrawIndexed(_: *ke.ke_gpu_device, rp: ?*anyopaque, idx_count: u32, inst_count: u32, first_idx: u32, base_vert: i32, first_inst: u32) callconv(.C) void {
    wgpu.wgpuRenderPassEncoderDrawIndexed(@ptrCast(rp), idx_count, inst_count, first_idx, base_vert, first_inst);
}

fn rpDrawIndirect(_: *ke.ke_gpu_device, rp: ?*anyopaque, indirect_buf: ke.ke_gpu_buffer, offset: usize) callconv(.C) void {
    wgpu.wgpuRenderPassEncoderDrawIndirect(@ptrCast(rp), @ptrFromInt(indirect_buf), offset);
}

fn rpEnd(_: *ke.ke_gpu_device, rp: ?*anyopaque) callconv(.C) void {
    wgpu.wgpuRenderPassEncoderEnd(@ptrCast(rp));
    wgpu.wgpuRenderPassEncoderRelease(@ptrCast(rp));
}

// ── Compute pass backing ───────────────────────────────────────────────────

fn cpSetPipeline(_: *ke.ke_gpu_device, cp: ?*anyopaque, pipe: ke.ke_gpu_pipeline) callconv(.C) void {
    wgpu.wgpuComputePassEncoderSetPipeline(@ptrCast(cp), @ptrFromInt(pipe));
}

fn cpSetBindGroup(_: *ke.ke_gpu_device, cp: ?*anyopaque, group_index: u32, bg: ke.ke_gpu_bind_group, dynamic_offsets: [*c]const u32, dyn_count: u32) callconv(.C) void {
    wgpu.wgpuComputePassEncoderSetBindGroup(@ptrCast(cp), group_index, @ptrFromInt(bg), dyn_count, dynamic_offsets);
}

fn cpDispatch(_: *ke.ke_gpu_device, cp: ?*anyopaque, x: u32, y: u32, z: u32) callconv(.C) void {
    wgpu.wgpuComputePassEncoderDispatchWorkgroups(@ptrCast(cp), x, y, z);
}

fn cpDispatchIndirect(_: *ke.ke_gpu_device, cp: ?*anyopaque, indirect_buf: ke.ke_gpu_buffer, offset: usize) callconv(.C) void {
    wgpu.wgpuComputePassEncoderDispatchWorkgroupsIndirect(@ptrCast(cp), @ptrFromInt(indirect_buf), offset);
}

fn cpEnd(_: *ke.ke_gpu_device, cp: ?*anyopaque) callconv(.C) void {
    wgpu.wgpuComputePassEncoderEnd(@ptrCast(cp));
    wgpu.wgpuComputePassEncoderRelease(@ptrCast(cp));
}

// ── Command buffer lifecycle ───────────────────────────────────────────────

fn cmdBufferDestroy(_: *ke.ke_gpu_device, cmd_buf: ?*anyopaque) callconv(.C) void {
    wgpu.wgpuCommandBufferRelease(@ptrCast(cmd_buf));
}

// ── Mapped writes ──────────────────────────────────────────────────────────

fn mapBuffer(_: *ke.ke_gpu_device, h: ke.ke_gpu_buffer, offset: usize, size: usize) callconv(.C) ?*anyopaque {
    return wgpu.wgpuBufferGetMappedRange(@ptrFromInt(h), offset, size);
}

fn mapBufferWrite(_: *ke.ke_gpu_device, h: ke.ke_gpu_buffer, offset: usize, size: usize) callconv(.C) ?*anyopaque {
    return wgpu.wgpuBufferGetMappedRange(@ptrFromInt(h), offset, size);
}

fn unmapBuffer(_: *ke.ke_gpu_device, h: ke.ke_gpu_buffer) callconv(.C) void {
    wgpu.wgpuBufferUnmap(@ptrFromInt(h));
}

// ── Capabilities ───────────────────────────────────────────────────────────

fn getCapabilities(_: *ke.ke_gpu_device, out: *ke.ke_gpu_capabilities) callconv(.C) void {
    out.* = std.mem.zeroes(ke.ke_gpu_capabilities);
    // TODO(R3): wgpuAdapterGetLimits / wgpuDeviceGetLimits
}

// ── Extension query ────────────────────────────────────────────────────────

fn queryExtension(_: *ke.ke_gpu_device, _: [*c]const u8) callconv(.C) ?*const anyopaque {
    return null;
}

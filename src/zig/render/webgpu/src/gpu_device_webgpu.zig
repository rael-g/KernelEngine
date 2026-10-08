const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

comptime {
    _ = @import("window_target.zig");
}
const builtin = @import("builtin");
pub const wgpu = @cImport({
    @cInclude("webgpu/webgpu.h");
    @cInclude("webgpu/wgpu.h");
});
pub const ke = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/render/gpu/gpu_device.h");
    @cInclude("kernel_engine/render/gpu/gpu_commands.h");
    @cInclude("kernel_engine/render/gpu/gpu_render_target.h");
    @cInclude("kernel_engine/window/window.h");
    @cInclude("kernel_engine/scheduler/scheduler.h");
});

const Params = extern struct {
    logger:            ?*anyopaque,
    enable_validation: ke.ke_bool,
    scheduler:         ?*ke.ke_scheduler,
};

const GpuError = error{
    OutOfMemory,
    NoAdapter,
    DeviceCreationFailed,
    NotImplemented,
};

pub const DeviceState = struct {
    instance:                wgpu.WGPUInstance,
    adapter:                 wgpu.WGPUAdapter,
    device:                  wgpu.WGPUDevice,
    queue:                   wgpu.WGPUQueue,
    scheduler:               ?*ke.ke_scheduler,
    pending_compiles:        [MAX_PENDING_COMPILES]?*ke.ke_task,
    pending_compiles_count:  u32,
};

const MAX_PENDING_COMPILES = 64;
const copy_row_alignment: u32 = 256;

fn ptr(dev: [*c]ke.ke_gpu_device) *ke.ke_gpu_device {
    return @ptrCast(dev);
}

pub fn state(dev: [*c]ke.ke_gpu_device) *DeviceState {
    return @ptrCast(@alignCast(ptr(dev).handle));
}

fn setError(
    out_error: ?*?*ke.ke_error,
    err: GpuError,
    msg: [*c]const u8,
    src: std.builtin.SourceLocation,
) void {
    const etype: *const ke.ke_error_type = switch (err) {
        GpuError.OutOfMemory           => &ke.KE_ERROR_OUT_OF_MEMORY,
        GpuError.NoAdapter,
        GpuError.DeviceCreationFailed  => &ke.KE_ERROR_NOT_INITIALIZED,
        GpuError.NotImplemented        => &ke.KE_ERROR_NOT_SUPPORTED,
    };
    ke.ke_error_set(out_error, etype, msg, src.file, @intCast(src.line), null);
}

fn toWgpuTextureFormat(f: ke.ke_gpu_texture_format) wgpu.WGPUTextureFormat {
    return switch (f) {
        ke.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM        => wgpu.WGPUTextureFormat_RGBA8Unorm,
        ke.KE_GPU_TEXTURE_FORMAT_RGBA8_SRGB         => wgpu.WGPUTextureFormat_RGBA8UnormSrgb,
        ke.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM        => wgpu.WGPUTextureFormat_BGRA8Unorm,
        ke.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT       => wgpu.WGPUTextureFormat_RGBA16Float,
        ke.KE_GPU_TEXTURE_FORMAT_R32_FLOAT          => wgpu.WGPUTextureFormat_R32Float,
        ke.KE_GPU_TEXTURE_FORMAT_R16_FLOAT          => wgpu.WGPUTextureFormat_R16Float,
        ke.KE_GPU_TEXTURE_FORMAT_D16_UNORM          => wgpu.WGPUTextureFormat_Depth16Unorm,
        ke.KE_GPU_TEXTURE_FORMAT_D24_UNORM_S8_UINT  => wgpu.WGPUTextureFormat_Depth24PlusStencil8,
        ke.KE_GPU_TEXTURE_FORMAT_D32_FLOAT          => wgpu.WGPUTextureFormat_Depth32Float,
        ke.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT  => wgpu.WGPUTextureFormat_Depth32FloatStencil8,
        ke.KE_GPU_TEXTURE_FORMAT_RGBA32_FLOAT       => wgpu.WGPUTextureFormat_RGBA32Float,
        ke.KE_GPU_TEXTURE_FORMAT_RG32_FLOAT         => wgpu.WGPUTextureFormat_RG32Float,
        ke.KE_GPU_TEXTURE_FORMAT_R8_UNORM           => wgpu.WGPUTextureFormat_R8Unorm,
        ke.KE_GPU_TEXTURE_FORMAT_BC1_RGBA_UNORM     => wgpu.WGPUTextureFormat_BC1RGBAUnorm,
        ke.KE_GPU_TEXTURE_FORMAT_BC3_RGBA_UNORM     => wgpu.WGPUTextureFormat_BC3RGBAUnorm,
        ke.KE_GPU_TEXTURE_FORMAT_BC5_RG_UNORM       => wgpu.WGPUTextureFormat_BC5RGUnorm,
        ke.KE_GPU_TEXTURE_FORMAT_BC7_RGBA_UNORM     => wgpu.WGPUTextureFormat_BC7RGBAUnorm,
        else                                        => wgpu.WGPUTextureFormat_Undefined,
    };
}

fn toWgpuTextureDimension(d: ke.ke_gpu_texture_dimension) wgpu.WGPUTextureDimension {
    return switch (d) {
        ke.KE_GPU_TEXTURE_DIM_1D   => wgpu.WGPUTextureDimension_1D,
        ke.KE_GPU_TEXTURE_DIM_2D,
        ke.KE_GPU_TEXTURE_DIM_CUBE => wgpu.WGPUTextureDimension_2D,
        ke.KE_GPU_TEXTURE_DIM_3D   => wgpu.WGPUTextureDimension_3D,
        else                       => wgpu.WGPUTextureDimension_2D,
    };
}

fn toWgpuTextureViewDimension(d: ke.ke_gpu_texture_dimension) wgpu.WGPUTextureViewDimension {
    return switch (d) {
        ke.KE_GPU_TEXTURE_DIM_1D   => wgpu.WGPUTextureViewDimension_1D,
        ke.KE_GPU_TEXTURE_DIM_2D   => wgpu.WGPUTextureViewDimension_2D,
        ke.KE_GPU_TEXTURE_DIM_3D   => wgpu.WGPUTextureViewDimension_3D,
        ke.KE_GPU_TEXTURE_DIM_CUBE => wgpu.WGPUTextureViewDimension_Cube,
        else                       => wgpu.WGPUTextureViewDimension_2D,
    };
}

fn toWgpuTextureAspect(a: ke.ke_gpu_texture_aspect) wgpu.WGPUTextureAspect {
    if (a & ke.KE_GPU_TEXTURE_ASPECT_DEPTH != 0) return wgpu.WGPUTextureAspect_DepthOnly;
    if (a & ke.KE_GPU_TEXTURE_ASPECT_STENCIL != 0) return wgpu.WGPUTextureAspect_StencilOnly;
    return wgpu.WGPUTextureAspect_All;
}

fn toWgpuLoadOp(op: ke.ke_gpu_load_op) wgpu.WGPULoadOp {
    return switch (op) {
        ke.KE_GPU_LOAD_OP_LOAD      => wgpu.WGPULoadOp_Load,
        ke.KE_GPU_LOAD_OP_CLEAR     => wgpu.WGPULoadOp_Clear,
        ke.KE_GPU_LOAD_OP_DONT_CARE => wgpu.WGPULoadOp_Undefined,
        else                        => wgpu.WGPULoadOp_Undefined,
    };
}

fn toWgpuStoreOp(op: ke.ke_gpu_store_op) wgpu.WGPUStoreOp {
    return switch (op) {
        ke.KE_GPU_STORE_OP_STORE      => wgpu.WGPUStoreOp_Store,
        ke.KE_GPU_STORE_OP_DONT_CARE  => wgpu.WGPUStoreOp_Discard,
        else                          => wgpu.WGPUStoreOp_Discard,
    };
}

fn toWgpuPrimitiveTopology(t: ke.ke_gpu_primitive_topology) wgpu.WGPUPrimitiveTopology {
    return switch (t) {
        ke.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST  => wgpu.WGPUPrimitiveTopology_TriangleList,
        ke.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP => wgpu.WGPUPrimitiveTopology_TriangleStrip,
        ke.KE_GPU_PRIMITIVE_TOPOLOGY_LINE_LIST      => wgpu.WGPUPrimitiveTopology_LineList,
        ke.KE_GPU_PRIMITIVE_TOPOLOGY_LINE_STRIP     => wgpu.WGPUPrimitiveTopology_LineStrip,
        ke.KE_GPU_PRIMITIVE_TOPOLOGY_POINT_LIST     => wgpu.WGPUPrimitiveTopology_PointList,
        else                                        => wgpu.WGPUPrimitiveTopology_TriangleList,
    };
}

fn toWgpuCullMode(m: ke.ke_gpu_cull_mode) wgpu.WGPUCullMode {
    return switch (m) {
        ke.KE_GPU_CULL_MODE_NONE  => wgpu.WGPUCullMode_None,
        ke.KE_GPU_CULL_MODE_FRONT => wgpu.WGPUCullMode_Front,
        ke.KE_GPU_CULL_MODE_BACK  => wgpu.WGPUCullMode_Back,
        else                      => wgpu.WGPUCullMode_None,
    };
}

fn toWgpuFrontFace(f: ke.ke_gpu_front_face) wgpu.WGPUFrontFace {
    return switch (f) {
        ke.KE_GPU_FRONT_FACE_CCW => wgpu.WGPUFrontFace_CCW,
        ke.KE_GPU_FRONT_FACE_CW  => wgpu.WGPUFrontFace_CW,
        else                     => wgpu.WGPUFrontFace_CCW,
    };
}

fn toWgpuVertexFormat(f: ke.ke_gpu_vertex_format) wgpu.WGPUVertexFormat {
    return switch (f) {
        ke.KE_GPU_VERTEX_FORMAT_FLOAT32X2    => wgpu.WGPUVertexFormat_Float32x2,
        ke.KE_GPU_VERTEX_FORMAT_FLOAT32X3    => wgpu.WGPUVertexFormat_Float32x3,
        ke.KE_GPU_VERTEX_FORMAT_FLOAT32X4    => wgpu.WGPUVertexFormat_Float32x4,
        ke.KE_GPU_VERTEX_FORMAT_SINT16X2     => wgpu.WGPUVertexFormat_Sint16x2,
        ke.KE_GPU_VERTEX_FORMAT_SINT16X4     => wgpu.WGPUVertexFormat_Sint16x4,
        ke.KE_GPU_VERTEX_FORMAT_UINT8X4_UNORM => wgpu.WGPUVertexFormat_Unorm8x4,
        ke.KE_GPU_VERTEX_FORMAT_UINT8X4      => wgpu.WGPUVertexFormat_Uint8x4,
        else                                 => wgpu.WGPUVertexFormat_Float32x4,
    };
}

fn toWgpuBlendFactor(f: ke.ke_gpu_blend_factor) wgpu.WGPUBlendFactor {
    return switch (f) {
        ke.KE_GPU_BLEND_FACTOR_ZERO                  => wgpu.WGPUBlendFactor_Zero,
        ke.KE_GPU_BLEND_FACTOR_ONE                   => wgpu.WGPUBlendFactor_One,
        ke.KE_GPU_BLEND_FACTOR_SRC_ALPHA             => wgpu.WGPUBlendFactor_SrcAlpha,
        ke.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA   => wgpu.WGPUBlendFactor_OneMinusSrcAlpha,
        ke.KE_GPU_BLEND_FACTOR_DST_ALPHA             => wgpu.WGPUBlendFactor_DstAlpha,
        ke.KE_GPU_BLEND_FACTOR_ONE_MINUS_DST_ALPHA   => wgpu.WGPUBlendFactor_OneMinusDstAlpha,
        ke.KE_GPU_BLEND_FACTOR_SRC_COLOR             => wgpu.WGPUBlendFactor_Src,
        ke.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_COLOR   => wgpu.WGPUBlendFactor_OneMinusSrc,
        ke.KE_GPU_BLEND_FACTOR_DST_COLOR             => wgpu.WGPUBlendFactor_Dst,
        ke.KE_GPU_BLEND_FACTOR_ONE_MINUS_DST_COLOR   => wgpu.WGPUBlendFactor_OneMinusDst,
        else                                         => wgpu.WGPUBlendFactor_Zero,
    };
}

fn toWgpuBlendOp(op: ke.ke_gpu_blend_op) wgpu.WGPUBlendOperation {
    return switch (op) {
        ke.KE_GPU_BLEND_OP_ADD              => wgpu.WGPUBlendOperation_Add,
        ke.KE_GPU_BLEND_OP_SUBTRACT         => wgpu.WGPUBlendOperation_Subtract,
        ke.KE_GPU_BLEND_OP_REVERSE_SUBTRACT => wgpu.WGPUBlendOperation_ReverseSubtract,
        ke.KE_GPU_BLEND_OP_MIN              => wgpu.WGPUBlendOperation_Min,
        ke.KE_GPU_BLEND_OP_MAX              => wgpu.WGPUBlendOperation_Max,
        else                                => wgpu.WGPUBlendOperation_Add,
    };
}

fn toWgpuCompareFunction(f: ke.ke_gpu_compare_function) wgpu.WGPUCompareFunction {
    return switch (f) {
        ke.KE_GPU_COMPARE_UNDEFINED     => wgpu.WGPUCompareFunction_Undefined,
        ke.KE_GPU_COMPARE_NEVER         => wgpu.WGPUCompareFunction_Never,
        ke.KE_GPU_COMPARE_LESS          => wgpu.WGPUCompareFunction_Less,
        ke.KE_GPU_COMPARE_EQUAL         => wgpu.WGPUCompareFunction_Equal,
        ke.KE_GPU_COMPARE_LESS_EQUAL    => wgpu.WGPUCompareFunction_LessEqual,
        ke.KE_GPU_COMPARE_GREATER       => wgpu.WGPUCompareFunction_Greater,
        ke.KE_GPU_COMPARE_NOT_EQUAL     => wgpu.WGPUCompareFunction_NotEqual,
        ke.KE_GPU_COMPARE_GREATER_EQUAL => wgpu.WGPUCompareFunction_GreaterEqual,
        ke.KE_GPU_COMPARE_ALWAYS        => wgpu.WGPUCompareFunction_Always,
        else                            => wgpu.WGPUCompareFunction_Undefined,
    };
}

fn toWgpuStencilOp(op: ke.ke_gpu_stencil_op) wgpu.WGPUStencilOperation {
    return switch (op) {
        ke.KE_GPU_STENCIL_OP_KEEP            => wgpu.WGPUStencilOperation_Keep,
        ke.KE_GPU_STENCIL_OP_ZERO            => wgpu.WGPUStencilOperation_Zero,
        ke.KE_GPU_STENCIL_OP_REPLACE         => wgpu.WGPUStencilOperation_Replace,
        ke.KE_GPU_STENCIL_OP_INVERT          => wgpu.WGPUStencilOperation_Invert,
        ke.KE_GPU_STENCIL_OP_INCREMENT_CLAMP => wgpu.WGPUStencilOperation_IncrementClamp,
        ke.KE_GPU_STENCIL_OP_DECREMENT_CLAMP => wgpu.WGPUStencilOperation_DecrementClamp,
        else                                 => wgpu.WGPUStencilOperation_Keep,
    };
}

fn toWgpuVertexStepMode(m: ke.ke_gpu_vertex_step_mode) wgpu.WGPUVertexStepMode {
    return switch (m) {
        ke.KE_GPU_VERTEX_STEP_MODE_VERTEX   => wgpu.WGPUVertexStepMode_Vertex,
        ke.KE_GPU_VERTEX_STEP_MODE_INSTANCE => wgpu.WGPUVertexStepMode_Instance,
        else                                => wgpu.WGPUVertexStepMode_Vertex,
    };
}

const heap = @import("heap");
pub const gpa = heap.gpa;

fn createDeviceState() GpuError!*DeviceState {
    const s = gpa.create(DeviceState) catch return GpuError.OutOfMemory;
    errdefer gpa.destroy(s);
    s.scheduler = null;
    s.pending_compiles = [_]?*ke.ke_task{null} ** MAX_PENDING_COMPILES;
    s.pending_compiles_count = 0;

    const instance_desc = wgpu.WGPUInstanceDescriptor{ .nextInChain = null };
    s.instance = wgpu.wgpuCreateInstance(&instance_desc) orelse
        return GpuError.DeviceCreationFailed;
    errdefer wgpu.wgpuInstanceRelease(s.instance);

    const adapter_opts = wgpu.WGPURequestAdapterOptions{
        .nextInChain          = null,
        .compatibleSurface    = null,
        .powerPreference      = wgpu.WGPUPowerPreference_HighPerformance,
        .backendType          = wgpu.WGPUBackendType_Undefined,
        .forceFallbackAdapter = 0,
    };
    var adapter: wgpu.WGPUAdapter = null;
    _ = wgpu.wgpuInstanceRequestAdapter(s.instance, &adapter_opts, .{
        .mode      = wgpu.WGPUCallbackMode_AllowSpontaneous,
        .callback  = adapterCallback,
        .userdata1 = @ptrCast(&adapter),
        .userdata2 = null,
    });
    s.adapter = adapter orelse return GpuError.NoAdapter;
    errdefer wgpu.wgpuAdapterRelease(s.adapter);

    var wgpu_device: wgpu.WGPUDevice = null;
    _ = wgpu.wgpuAdapterRequestDevice(s.adapter, null, .{
        .mode      = wgpu.WGPUCallbackMode_AllowSpontaneous,
        .callback  = deviceCallback,
        .userdata1 = @ptrCast(&wgpu_device),
        .userdata2 = null,
    });
    s.device = wgpu_device orelse return GpuError.DeviceCreationFailed;
    errdefer wgpu.wgpuDeviceRelease(s.device);

    s.queue = wgpu.wgpuDeviceGetQueue(s.device);

    return s;
}

fn createDeviceVtable(s: *DeviceState) GpuError!*ke.ke_gpu_device {
    const dev = gpa.create(ke.ke_gpu_device) catch return GpuError.OutOfMemory;
    dev.* = .{
        .handle                         = s,
        .get_default_queue              = getDefaultQueue,
        .queue_submit                   = queueSubmit,
        .queue_poll                     = queuePoll,
        .queue_wait_idle                = queueWaitIdle,
        .create_fence                   = createFence,
        .queue_signal_fence             = queueSignalFence,
        .wait_fence                     = waitFence,
        .get_fence_value                = getFenceValue,
        .destroy_fence                  = destroyFence,
        .create_buffer                  = createBuffer,
        .create_texture                 = createTexture,
        .create_texture_view            = createTextureView,
        .create_sampler                 = createSampler,
        .create_shader_module           = createShaderModule,
        .create_render_pipeline         = createRenderPipeline,
        .create_compute_pipeline        = createComputePipeline,
        .create_bind_group_layout       = createBindGroupLayout,
        .create_bind_group              = createBindGroup,
        .destroy_buffer                 = destroyBuffer,
        .destroy_texture                = destroyTexture,
        .destroy_texture_view           = destroyTextureView,
        .destroy_sampler                = destroySampler,
        .destroy_shader_module          = destroyShaderModule,
        .destroy_pipeline               = destroyPipeline,
        .destroy_bind_group_layout      = destroyBindGroupLayout,
        .destroy_bind_group             = destroyBindGroup,
        .create_command_encoder         = createCommandEncoder,
        .write_buffer                   = writeBuffer,
        .map_buffer                     = mapBuffer,
        .map_buffer_write               = mapBufferWrite,
        .unmap_buffer                   = unmapBuffer,
        .get_capabilities               = getCapabilities,
        .shader_language                = shaderLanguage,
        .get_ndc_convention             = getNdcConvention,
        .query_extension                = queryExtension,
        .create_render_pipeline_async   = createRenderPipelineAsync,
        .flush_pipeline_compiles        = flushPipelineCompiles,
        .map_buffer_read                = mapBufferRead,
        .destroy_compute_pipeline       = destroyComputePipeline,
    };
    return dev;
}

pub export fn ke_gpu_device_webgpu_create(
    params: ?*const Params,
    out_error: ?*?*ke.ke_error,
) ke.ke_gpu_device_handle {
    const s = createDeviceState() catch |err| {
        setError(out_error, err, "webgpu: device initialisation failed", @src());
        return .{ .ref = null, .destroy = null };
    };
    s.scheduler = if (params) |p| p.scheduler else null;

    const dev = createDeviceVtable(s) catch |err| {
        setError(out_error, err, "webgpu: vtable allocation failed", @src());
        wgpu.wgpuQueueRelease(s.queue);
        wgpu.wgpuDeviceRelease(s.device);
        wgpu.wgpuAdapterRelease(s.adapter);
        wgpu.wgpuInstanceRelease(s.instance);
        gpa.destroy(s);
        return .{ .ref = null, .destroy = null };
    };

    return .{ .ref = dev, .destroy = deviceDestroy };
}

fn deviceDestroy(dev: [*c]ke.ke_gpu_device) callconv(.c) void {
    const s = state(dev);
    wgpu.wgpuQueueRelease(s.queue);
    wgpu.wgpuDeviceRelease(s.device);
    wgpu.wgpuAdapterRelease(s.adapter);
    wgpu.wgpuInstanceRelease(s.instance);
    gpa.destroy(s);
    gpa.destroy(ptr(dev));
}

fn adapterCallback(
    _: wgpu.WGPURequestAdapterStatus,
    adapter: wgpu.WGPUAdapter,
    _: wgpu.WGPUStringView,
    userdata1: ?*anyopaque,
    _: ?*anyopaque,
) callconv(.c) void {
    const out: *wgpu.WGPUAdapter = @ptrCast(@alignCast(userdata1));
    out.* = adapter;
}

fn deviceCallback(
    _: wgpu.WGPURequestDeviceStatus,
    device: wgpu.WGPUDevice,
    _: wgpu.WGPUStringView,
    userdata1: ?*anyopaque,
    _: ?*anyopaque,
) callconv(.c) void {
    const out: *wgpu.WGPUDevice = @ptrCast(@alignCast(userdata1));
    out.* = device;
}

pub fn getDefaultQueue(dev: [*c]ke.ke_gpu_device) callconv(.c) ke.ke_gpu_queue {
    return @intFromPtr(state(dev).queue);
}

fn queueSubmit(
    _: [*c]ke.ke_gpu_device,
    q: ke.ke_gpu_queue,
    cmds: [*c]const ?*ke.ke_gpu_command_buffer,
    cmd_count: u32,
) callconv(.c) void {
    if (cmd_count == 0) return;
    var buf: [64]wgpu.WGPUCommandBuffer = undefined;
    const n = @min(cmd_count, buf.len);
    for (0..n) |i| buf[i] = @ptrCast(cmds[i].?.handle);
    wgpu.wgpuQueueSubmit(@ptrFromInt(q), @intCast(n), &buf);
}

fn reapCompletedCompiles(s: *DeviceState) void {
    const sched = s.scheduler orelse return;
    var i: u32 = 0;
    while (i < s.pending_compiles_count) {
        const task = s.pending_compiles[i].?;
        if (sched.is_completed.?(sched, task)) {
            _ = sched.wait.?(sched, task, null);
            s.pending_compiles_count -= 1;
            s.pending_compiles[i] = s.pending_compiles[s.pending_compiles_count];
            continue;
        }
        i += 1;
    }
}

fn queuePoll(dev: [*c]ke.ke_gpu_device, _: ke.ke_gpu_queue) callconv(.c) void {
    const s = state(dev);
    reapCompletedCompiles(s);
    _ = wgpu.wgpuDevicePoll(s.device, 0, null);
}

fn queueWaitIdle(dev: [*c]ke.ke_gpu_device, _: ke.ke_gpu_queue) callconv(.c) void {
    _ = wgpu.wgpuDevicePoll(state(dev).device, 1, null);
}

fn createFence(_: [*c]ke.ke_gpu_device, _: u64) callconv(.c) ke.ke_gpu_fence { return ke.KE_GPU_INVALID_HANDLE; }
fn queueSignalFence(_: [*c]ke.ke_gpu_device, _: ke.ke_gpu_queue, _: ke.ke_gpu_fence, _: u64) callconv(.c) void {}
fn waitFence(_: [*c]ke.ke_gpu_device, _: ke.ke_gpu_fence, _: u64, _: u64, out_error: ?*?*ke.ke_error) callconv(.c) bool {
    setError(out_error, GpuError.NotImplemented, "webgpu: timeline fences not implemented", @src());
    return false;
}
fn getFenceValue(_: [*c]ke.ke_gpu_device, _: ke.ke_gpu_fence) callconv(.c) u64 { return 0; }
fn destroyFence(_: [*c]ke.ke_gpu_device, _: ke.ke_gpu_fence) callconv(.c) void {}

fn mapBufferUsage(ke_usage: ke.ke_gpu_buffer_usage) wgpu.WGPUBufferUsage {
    var u: wgpu.WGPUBufferUsage = wgpu.WGPUBufferUsage_None;
    if (ke_usage & ke.KE_GPU_BUFFER_USAGE_MAP_READ  != 0) u |= wgpu.WGPUBufferUsage_MapRead;
    if (ke_usage & ke.KE_GPU_BUFFER_USAGE_MAP_WRITE != 0) u |= wgpu.WGPUBufferUsage_MapWrite;
    if (ke_usage & ke.KE_GPU_BUFFER_USAGE_COPY_SRC  != 0) u |= wgpu.WGPUBufferUsage_CopySrc;
    if (ke_usage & ke.KE_GPU_BUFFER_USAGE_COPY_DST  != 0) u |= wgpu.WGPUBufferUsage_CopyDst;
    if (ke_usage & ke.KE_GPU_BUFFER_USAGE_INDEX     != 0) u |= wgpu.WGPUBufferUsage_Index;
    if (ke_usage & ke.KE_GPU_BUFFER_USAGE_VERTEX    != 0) u |= wgpu.WGPUBufferUsage_Vertex;
    if (ke_usage & ke.KE_GPU_BUFFER_USAGE_UNIFORM   != 0) u |= wgpu.WGPUBufferUsage_Uniform;
    if (ke_usage & ke.KE_GPU_BUFFER_USAGE_STORAGE   != 0) u |= wgpu.WGPUBufferUsage_Storage;
    if (ke_usage & ke.KE_GPU_BUFFER_USAGE_INDIRECT  != 0) u |= wgpu.WGPUBufferUsage_Indirect;
    return u;
}

fn mapTextureUsage(ke_usage: ke.ke_gpu_texture_usage) wgpu.WGPUTextureUsage {
    var u: wgpu.WGPUTextureUsage = wgpu.WGPUTextureUsage_None;
    if (ke_usage & ke.KE_GPU_TEXTURE_USAGE_COPY_SRC     != 0) u |= wgpu.WGPUTextureUsage_CopySrc;
    if (ke_usage & ke.KE_GPU_TEXTURE_USAGE_COPY_DST     != 0) u |= wgpu.WGPUTextureUsage_CopyDst;
    if (ke_usage & ke.KE_GPU_TEXTURE_USAGE_SAMPLED      != 0) u |= wgpu.WGPUTextureUsage_TextureBinding;
    if (ke_usage & ke.KE_GPU_TEXTURE_USAGE_STORAGE      != 0) u |= wgpu.WGPUTextureUsage_StorageBinding;
    if (ke_usage & ke.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH != 0) u |= wgpu.WGPUTextureUsage_RenderAttachment;
    if (ke_usage & ke.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH != 0) u |= wgpu.WGPUTextureUsage_RenderAttachment;
    return u;
}

fn mapShaderStage(ke_stage: ke.ke_gpu_shader_stage) wgpu.WGPUShaderStage {
    var s: wgpu.WGPUShaderStage = wgpu.WGPUShaderStage_None;
    if (ke_stage & ke.KE_GPU_SHADER_STAGE_VERTEX   != 0) s |= wgpu.WGPUShaderStage_Vertex;
    if (ke_stage & ke.KE_GPU_SHADER_STAGE_FRAGMENT != 0) s |= wgpu.WGPUShaderStage_Fragment;
    if (ke_stage & ke.KE_GPU_SHADER_STAGE_COMPUTE  != 0) s |= wgpu.WGPUShaderStage_Compute;
    return s;
}

fn createBuffer(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_buffer_params, out_error: ?*?*ke.ke_error) callconv(.c) ke.ke_gpu_buffer {
    const pp = @as(*const ke.ke_gpu_buffer_params, @ptrCast(p));
    const s = state(dev);
    var usage = mapBufferUsage(pp.usage);
    if (pp.initial_data != null) usage |= wgpu.WGPUBufferUsage_CopyDst;
    const desc = wgpu.WGPUBufferDescriptor{
        .nextInChain      = null,
        .label            = .{ .data = null, .length = 0 },
        .usage            = usage,
        .size             = pp.size,
        .mappedAtCreation = if (pp.mapped_at_creation != 0) 1 else 0,
    };

    wgpu.wgpuDevicePushErrorScope(s.device, wgpu.WGPUErrorFilter_Validation);
    const buf: wgpu.WGPUBuffer = wgpu.wgpuDeviceCreateBuffer(s.device, &desc);
    var se = ScopeError{ .captured = false, .buf = undefined };
    _ = wgpu.wgpuDevicePopErrorScope(s.device, .{
        .nextInChain = null,
        .mode      = wgpu.WGPUCallbackMode_AllowSpontaneous,
        .callback  = popErrorCallback,
        .userdata1 = &se,
        .userdata2 = null,
    });
    _ = wgpu.wgpuDevicePoll(s.device, 1, null);

    if (se.captured) {
        ke.ke_error_set(out_error, &KE_ERROR_WGPU_RESOURCE_CREATION, &se.buf, @src().file, @intCast(@src().line), null);
        if (buf != null) wgpu.wgpuBufferRelease(buf);
        return ke.KE_GPU_INVALID_HANDLE;
    }
    const handle = buf orelse return ke.KE_GPU_INVALID_HANDLE;
    if (pp.initial_data != null) wgpu.wgpuQueueWriteBuffer(s.queue, handle, 0, pp.initial_data, pp.size);
    return @intFromPtr(handle);
}

fn createTexture(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_texture_params) callconv(.c) ke.ke_gpu_texture {
    const pp = @as(*const ke.ke_gpu_texture_params, @ptrCast(p));
    const s = state(dev);
    var usage = mapTextureUsage(pp.usage);
    if (pp.initial_data != null) usage |= wgpu.WGPUTextureUsage_CopyDst;
    const fmt = toWgpuTextureFormat(pp.format);
    const desc = wgpu.WGPUTextureDescriptor{
        .nextInChain     = null,
        .label           = .{ .data = null, .length = 0 },
        .usage           = usage,
        .dimension       = toWgpuTextureDimension(pp.dimension),
        .size            = .{ .width = pp.width, .height = pp.height, .depthOrArrayLayers = if (pp.depth_or_array_layers == 0) 1 else pp.depth_or_array_layers },
        .format          = fmt,
        .mipLevelCount   = if (pp.mip_level_count == 0) 1 else pp.mip_level_count,
        .sampleCount     = if (pp.sample_count == 0) 1 else pp.sample_count,
        .viewFormatCount = 0,
        .viewFormats     = null,
    };
    const tex: wgpu.WGPUTexture = wgpu.wgpuDeviceCreateTexture(s.device, &desc) orelse return ke.KE_GPU_INVALID_HANDLE;
    if (pp.initial_data != null) {
        const bytes_per_pixel: u32 = 4;
        const unaligned_bpr: u32 = pp.width * bytes_per_pixel;
        const bytes_per_row: u32 = std.mem.alignForward(u32, unaligned_bpr, copy_row_alignment);
        const face_bytes: usize = @as(usize, unaligned_bpr) * pp.height;
        const layers: u32 = if (pp.depth_or_array_layers == 0) 1 else pp.depth_or_array_layers;
        const src_bytes: [*]const u8 = @ptrCast(pp.initial_data);
        const layout = wgpu.WGPUTexelCopyBufferLayout{
            .offset       = 0,
            .bytesPerRow  = bytes_per_row,
            .rowsPerImage = pp.height,
        };
        const extent = wgpu.WGPUExtent3D{ .width = pp.width, .height = pp.height, .depthOrArrayLayers = 1 };
        var layer: u32 = 0;
        while (layer < layers) : (layer += 1) {
            const dst = wgpu.WGPUTexelCopyTextureInfo{
                .texture  = tex,
                .mipLevel = 0,
                .origin   = .{ .x = 0, .y = 0, .z = layer },
                .aspect   = wgpu.WGPUTextureAspect_All,
            };
            const src_off = @as(usize, layer) * face_bytes;
            if (bytes_per_row == unaligned_bpr) {
                wgpu.wgpuQueueWriteTexture(s.queue, &dst, src_bytes + src_off, face_bytes, &layout, &extent);
            } else {
                const staging_size = bytes_per_row * pp.height;
                const staging = std.heap.page_allocator.alloc(u8, staging_size) catch return @intFromPtr(tex);
                defer std.heap.page_allocator.free(staging);
                for (0..pp.height) |row| {
                    const so = src_off + row * unaligned_bpr;
                    const do = row * bytes_per_row;
                    @memcpy(staging[do .. do + unaligned_bpr], src_bytes[so .. so + unaligned_bpr]);
                }
                wgpu.wgpuQueueWriteTexture(s.queue, &dst, staging.ptr, staging_size, &layout, &extent);
            }
        }
    }
    return @intFromPtr(tex);
}

fn createTextureView(_: [*c]ke.ke_gpu_device, tex: ke.ke_gpu_texture, p: [*c]const ke.ke_gpu_texture_view_params) callconv(.c) ke.ke_gpu_texture_view {
    const pp = @as(*const ke.ke_gpu_texture_view_params, @ptrCast(p));
    const desc = wgpu.WGPUTextureViewDescriptor{
        .nextInChain     = null,
        .label           = .{ .data = null, .length = 0 },
        .format          = toWgpuTextureFormat(pp.format),
        .dimension       = toWgpuTextureViewDimension(pp.dimension),
        .aspect          = toWgpuTextureAspect(pp.aspect),
        .baseMipLevel    = pp.base_mip_level,
        .mipLevelCount   = if (pp.mip_level_count == 0) 1 else pp.mip_level_count,
        .baseArrayLayer  = pp.base_array_layer,
        .arrayLayerCount = if (pp.array_layer_count == 0) 1 else pp.array_layer_count,
    };
    const wgpu_tex: wgpu.WGPUTexture = @ptrFromInt(tex);
    return @intFromPtr(wgpu.wgpuTextureCreateView(wgpu_tex, &desc));
}

fn createSampler(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_sampler_params) callconv(.c) ke.ke_gpu_sampler {
    const pp = @as(*const ke.ke_gpu_sampler_params, @ptrCast(p));
    const desc = wgpu.WGPUSamplerDescriptor{
        .nextInChain   = null,
        .label         = .{ .data = null, .length = 0 },
        .addressModeU  = @intCast(pp.address_mode_u),
        .addressModeV  = @intCast(pp.address_mode_v),
        .addressModeW  = @intCast(pp.address_mode_w),
        .magFilter     = @intCast(pp.mag_filter),
        .minFilter     = @intCast(pp.min_filter),
        .mipmapFilter  = @intCast(pp.mipmap_filter),
        .lodMinClamp   = pp.lod_min_clamp,
        .lodMaxClamp   = pp.lod_max_clamp,
        .compare       = toWgpuCompareFunction(pp.compare),
        .maxAnisotropy = pp.max_anisotropy,
    };
    return @intFromPtr(wgpu.wgpuDeviceCreateSampler(state(dev).device, &desc));
}

fn shaderLanguage(_: [*c]ke.ke_gpu_device) callconv(.c) ke.ke_gpu_shader_language {
    return ke.KE_GPU_SHADER_LANG_WGSL;
}

fn getNdcConvention(_: [*c]ke.ke_gpu_device) callconv(.c) ke.ke_ndc_convention {
    return .{ .z_zero_to_one = 1, .y_flip = 0, .clip_left_handed = 1 };
}

const SPIRV_MAGIC: u32 = 0x07230203;

export const KE_ERROR_GPU_SHADER_COMPILATION: ke.ke_error_type = .{
    .name = "ke.render.gpu.shader_compilation",
    .parent = &ke.KE_ERROR_INVALID_ARGUMENT,
};
export const KE_ERROR_WGPU_SHADER_COMPILATION: ke.ke_error_type = .{
    .name = "ke.render.gpu.wgpu.shader_compilation",
    .parent = &KE_ERROR_GPU_SHADER_COMPILATION,
};
export const KE_ERROR_GPU_RESOURCE_CREATION: ke.ke_error_type = .{
    .name = "ke.render.gpu.resource_creation",
    .parent = &ke.KE_ERROR_INVALID_ARGUMENT,
};
export const KE_ERROR_WGPU_RESOURCE_CREATION: ke.ke_error_type = .{
    .name = "ke.render.gpu.wgpu.resource_creation",
    .parent = &KE_ERROR_GPU_RESOURCE_CREATION,
};

const ScopeError = struct {
    captured: bool,
    buf: [512]u8,
};

fn popErrorCallback(
    _: wgpu.WGPUPopErrorScopeStatus,
    etype: wgpu.WGPUErrorType,
    message: wgpu.WGPUStringView,
    ud1: ?*anyopaque,
    _: ?*anyopaque,
) callconv(.c) void {
    const se: *ScopeError = @ptrCast(@alignCast(ud1));
    if (etype == wgpu.WGPUErrorType_NoError) return;
    se.captured = true;
    if (message.data != null and message.length > 0) {
        const n = @min(message.length, se.buf.len - 1);
        @memcpy(se.buf[0..n], message.data[0..n]);
        se.buf[n] = 0;
    } else {
        se.buf[0] = 0;
    }
}

fn createShaderModule(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_shader_module_params, out_error: ?*?*ke.ke_error) callconv(.c) ke.ke_gpu_shader_module {
    const pp = @as(*const ke.ke_gpu_shader_module_params, @ptrCast(p));
    const device = state(dev).device;

    const is_spirv = pp.byte_size >= 4 and
        @as(*align(1) const u32, @ptrCast(pp.code)).* == SPIRV_MAGIC;

    var desc = wgpu.WGPUShaderModuleDescriptor{
        .nextInChain = null,
        .label       = .{ .data = pp.entry_point, .length = wgpu.WGPU_STRLEN },
    };
    var spirv: wgpu.WGPUShaderSourceSPIRV = undefined;
    const wgsl = wgpu.WGPUShaderSourceWGSL{
        .chain = .{ .next = null, .sType = wgpu.WGPUSType_ShaderSourceWGSL },
        .code  = .{ .data = @ptrCast(pp.code), .length = if (pp.byte_size != 0) pp.byte_size else wgpu.WGPU_STRLEN },
    };
    if (is_spirv) {
        spirv = .{
            .chain    = .{ .next = null, .sType = wgpu.WGPUSType_ShaderSourceSPIRV },
            .codeSize = @intCast(pp.byte_size / 4),
            .code     = @ptrCast(@alignCast(pp.code)),
        };
        desc.nextInChain = @ptrCast(&spirv);
    } else {
        desc.nextInChain = @ptrCast(&wgsl);
    }

    wgpu.wgpuDevicePushErrorScope(device, wgpu.WGPUErrorFilter_Validation);
    const handle = wgpu.wgpuDeviceCreateShaderModule(device, &desc);
    var se = ScopeError{ .captured = false, .buf = undefined };
    _ = wgpu.wgpuDevicePopErrorScope(device, .{
        .nextInChain = null,
        .mode      = wgpu.WGPUCallbackMode_AllowSpontaneous,
        .callback  = popErrorCallback,
        .userdata1 = &se,
        .userdata2 = null,
    });
    _ = wgpu.wgpuDevicePoll(device, 1, null);

    if (se.captured) {
        ke.ke_error_set(out_error, &KE_ERROR_WGPU_SHADER_COMPILATION, &se.buf, @src().file, @intCast(@src().line), null);
        if (handle != null) wgpu.wgpuShaderModuleRelease(handle);
        return ke.KE_GPU_INVALID_HANDLE;
    }
    return @intFromPtr(handle);
}

const RenderPipelineDescBuild = struct {
    desc: wgpu.WGPURenderPipelineDescriptor,
    pipeline_layout: wgpu.WGPUPipelineLayout,
    wgpu_attrs: [32]wgpu.WGPUVertexAttribute,
    wgpu_bufs: [8]wgpu.WGPUVertexBufferLayout,
    color_targets: [8]wgpu.WGPUColorTargetState,
    wgpu_blend: wgpu.WGPUBlendState,
    ds_state: wgpu.WGPUDepthStencilState,
    frag_state: wgpu.WGPUFragmentState,
    bgl_handles: [4]wgpu.WGPUBindGroupLayout,
};

fn buildRenderPipelineDescriptor(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_render_pipeline_params, build: *RenderPipelineDescBuild) void {
    const pp = @as(*const ke.ke_gpu_render_pipeline_params, @ptrCast(p));

    var attr_offset: usize = 0;
    const buf_count = @min(pp.vertex_buffer_count, build.wgpu_bufs.len);

    for (0..buf_count) |bi| {
        const src_buf = @as(*const ke.ke_gpu_vertex_buffer_layout, @ptrCast(&pp.vertex_buffers[bi]));
        const ac = @min(src_buf.attribute_count, 32 - attr_offset);
        for (0..ac) |ai| {
            const src_a = @as(*const ke.ke_gpu_vertex_attribute, @ptrCast(&src_buf.attributes[ai]));
            build.wgpu_attrs[attr_offset + ai] = .{
                .format         = toWgpuVertexFormat(src_a.format),
                .offset         = src_a.offset,
                .shaderLocation = src_a.shader_location,
            };
        }
        build.wgpu_bufs[bi] = .{
            .arrayStride    = src_buf.stride,
            .stepMode       = toWgpuVertexStepMode(src_buf.step_mode),
            .attributeCount = ac,
            .attributes     = &build.wgpu_attrs[attr_offset],
        };
        attr_offset += ac;
    }

    const target_count = @min(@max(pp.color_target_count, 1), 8);
    const bs = pp.blend_state;
    build.wgpu_blend = .{
        .color = .{
            .srcFactor = toWgpuBlendFactor(bs.src_color),
            .dstFactor = toWgpuBlendFactor(bs.dst_color),
            .operation = toWgpuBlendOp(bs.color_op),
        },
        .alpha = .{
            .srcFactor = toWgpuBlendFactor(bs.src_alpha),
            .dstFactor = toWgpuBlendFactor(bs.dst_alpha),
            .operation = toWgpuBlendOp(bs.alpha_op),
        },
    };
    for (0..target_count) |ti| {
        const fmt = pp.color_target_formats[ti];
        build.color_targets[ti] = .{
            .nextInChain = null,
            .format      = toWgpuTextureFormat(fmt),
            .blend       = if (bs.blend_enabled != 0) &build.wgpu_blend else null,
            .writeMask   = pp.blend_state.write_mask,
        };
    }
    build.frag_state = .{
        .nextInChain  = null,
        .module       = @ptrFromInt(pp.fragment_module),
        .entryPoint   = .{ .data = if (pp.fragment_entry != null) pp.fragment_entry else "main", .length = wgpu.WGPU_STRLEN },
        .constantCount = 0,
        .constants    = null,
        .targetCount  = target_count,
        .targets      = &build.color_targets,
    };

    const ds = pp.depth_stencil;
    build.ds_state = .{
        .nextInChain         = null,
        .format              = wgpu.WGPUTextureFormat_Depth32Float,
        .depthWriteEnabled   = if (ds.depth_write_enabled != 0) @intFromBool(true) else @intFromBool(false),
        .depthCompare        = toWgpuCompareFunction(ds.depth_compare),
        .stencilFront        = .{
            .compare     = toWgpuCompareFunction(ds.stencil_front_compare),
            .failOp      = toWgpuStencilOp(ds.stencil_front_fail),
            .depthFailOp = toWgpuStencilOp(ds.stencil_front_depth_fail),
            .passOp      = toWgpuStencilOp(ds.stencil_front_pass),
        },
        .stencilBack         = .{
            .compare     = toWgpuCompareFunction(ds.stencil_back_compare),
            .failOp      = toWgpuStencilOp(ds.stencil_back_fail),
            .depthFailOp = toWgpuStencilOp(ds.stencil_back_depth_fail),
            .passOp      = toWgpuStencilOp(ds.stencil_back_pass),
        },
        .stencilReadMask     = ds.stencil_read_mask,
        .stencilWriteMask    = ds.stencil_write_mask,
        .depthBias           = 0,
        .depthBiasSlopeScale = 0.0,
        .depthBiasClamp      = 0.0,
    };

    build.pipeline_layout = null;
    if (pp.bind_group_layout_count > 0) {
        const bgl_count = @min(pp.bind_group_layout_count, build.bgl_handles.len);
        for (0..bgl_count) |i| build.bgl_handles[i] = @ptrFromInt(pp.bind_group_layouts[i]);
        const layout_desc = wgpu.WGPUPipelineLayoutDescriptor{
            .nextInChain          = null,
            .label                = .{ .data = null, .length = 0 },
            .bindGroupLayoutCount = bgl_count,
            .bindGroupLayouts     = &build.bgl_handles,
        };
        build.pipeline_layout = wgpu.wgpuDeviceCreatePipelineLayout(state(dev).device, &layout_desc);
    }

    build.desc = .{
        .nextInChain = null,
        .label       = .{ .data = null, .length = 0 },
        .layout      = build.pipeline_layout,
        .vertex      = .{
            .nextInChain   = null,
            .module        = @ptrFromInt(pp.vertex_module),
            .entryPoint    = .{ .data = if (pp.vertex_entry != null) pp.vertex_entry else "main", .length = wgpu.WGPU_STRLEN },
            .constantCount = 0,
            .constants     = null,
            .bufferCount   = buf_count,
            .buffers       = if (buf_count > 0) &build.wgpu_bufs else null,
        },
        .primitive   = .{
            .nextInChain      = null,
            .topology         = toWgpuPrimitiveTopology(pp.primitive_topology),
            .stripIndexFormat = wgpu.WGPUIndexFormat_Undefined,
            .frontFace        = toWgpuFrontFace(pp.front_face),
            .cullMode         = toWgpuCullMode(pp.cull_mode),
        },
        .depthStencil = if (ds.depth_test_enabled != 0) &build.ds_state else null,
        .multisample  = .{
            .nextInChain            = null,
            .count                  = 1,
            .mask                   = 0xFFFFFFFF,
            .alphaToCoverageEnabled = if (pp.alpha_to_coverage_enabled != 0) 1 else 0,
        },
        .fragment = &build.frag_state,
    };
}

fn colorTargetsDeclared(p: [*c]const ke.ke_gpu_render_pipeline_params) bool {
    if (p.*.fragment_module == ke.KE_GPU_INVALID_HANDLE) return true;
    const count = @min(@max(p.*.color_target_count, 1), 8);
    for (p.*.color_target_formats[0..count]) |f| {
        if (toWgpuTextureFormat(f) == wgpu.WGPUTextureFormat_Undefined) return false;
    }
    return true;
}

fn createRenderPipeline(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_render_pipeline_params) callconv(.c) ke.ke_gpu_pipeline {
    if (!colorTargetsDeclared(p)) return ke.KE_GPU_INVALID_HANDLE;
    var build: RenderPipelineDescBuild = undefined;
    buildRenderPipelineDescriptor(dev, p, &build);
    defer if (build.pipeline_layout != null) wgpu.wgpuPipelineLayoutRelease(build.pipeline_layout);
    return @intFromPtr(wgpu.wgpuDeviceCreateRenderPipeline(state(dev).device, &build.desc));
}

const AsyncCompileJob = struct {
    device: wgpu.WGPUDevice,
    build: RenderPipelineDescBuild,
    on_ready: *const fn (ke.ke_gpu_pipeline, ?*anyopaque) callconv(.c) void,
    user: ?*anyopaque,
};

extern "kernel32" fn Sleep(dwMilliseconds: c_ulong) callconv(.winapi) void;
extern "c" fn usleep(usec: c_uint) c_int;

fn debugAsyncDelayMs(build: *const RenderPipelineDescBuild) u64 {
    const raw = std.c.getenv("KE_PSO_ASYNC_DELAY_MS") orelse return 0;
    const ms = std.fmt.parseInt(u64, std.mem.span(raw), 10) catch 0;
    if (ms == 0) return 0;
    if (std.c.getenv("KE_PSO_ASYNC_DELAY_BLEND_ONLY") != null) {
        const blend_enabled = build.frag_state.targetCount > 0 and build.color_targets[0].blend != null;
        if (!blend_enabled) return 0;
    }
    return ms;
}

fn debugSleepMs(ms: u64) void {
    if (ms == 0) return;
    if (builtin.target.os.tag == .windows) {
        Sleep(@intCast(ms));
    } else {
        _ = usleep(@intCast(ms * 1000));
    }
}

fn runAsyncCompileJob(data: ?*anyopaque, out_failure: [*c][*c]const ke.ke_error_type) callconv(.c) void {
    _ = out_failure;
    const job: *AsyncCompileJob = @ptrCast(@alignCast(data.?));
    debugSleepMs(debugAsyncDelayMs(&job.build));
    const pipeline = wgpu.wgpuDeviceCreateRenderPipeline(job.device, &job.build.desc);
    if (job.build.pipeline_layout != null) wgpu.wgpuPipelineLayoutRelease(job.build.pipeline_layout);
    if (job.build.desc.vertex.module) |m| wgpu.wgpuShaderModuleRelease(m);
    if (job.build.frag_state.module) |m| wgpu.wgpuShaderModuleRelease(m);
    job.on_ready(if (pipeline != null) @intFromPtr(pipeline) else ke.KE_GPU_INVALID_HANDLE, job.user);
    gpa.destroy(job);
}

fn createRenderPipelineAsync(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_render_pipeline_params,
                             on_ready: ?*const fn (ke.ke_gpu_pipeline, ?*anyopaque) callconv(.c) void, user: ?*anyopaque) callconv(.c) void {
    const cb = on_ready orelse return;
    const s = state(dev);
    if (!colorTargetsDeclared(p)) {
        cb(ke.KE_GPU_INVALID_HANDLE, user);
        return;
    }

    const sched = s.scheduler orelse {
        var build: RenderPipelineDescBuild = undefined;
        buildRenderPipelineDescriptor(dev, p, &build);
        defer if (build.pipeline_layout != null) wgpu.wgpuPipelineLayoutRelease(build.pipeline_layout);
        const pipeline = wgpu.wgpuDeviceCreateRenderPipeline(s.device, &build.desc);
        cb(if (pipeline != null) @intFromPtr(pipeline) else ke.KE_GPU_INVALID_HANDLE, user);
        return;
    };

    reapCompletedCompiles(s);
    if (s.pending_compiles_count >= MAX_PENDING_COMPILES) {
        var build: RenderPipelineDescBuild = undefined;
        buildRenderPipelineDescriptor(dev, p, &build);
        defer if (build.pipeline_layout != null) wgpu.wgpuPipelineLayoutRelease(build.pipeline_layout);
        const pipeline = wgpu.wgpuDeviceCreateRenderPipeline(s.device, &build.desc);
        cb(if (pipeline != null) @intFromPtr(pipeline) else ke.KE_GPU_INVALID_HANDLE, user);
        return;
    }

    const job = gpa.create(AsyncCompileJob) catch {
        cb(ke.KE_GPU_INVALID_HANDLE, user);
        return;
    };
    job.device = s.device;
    job.on_ready = cb;
    job.user = user;
    buildRenderPipelineDescriptor(dev, p, &job.build);
    if (job.build.desc.vertex.module) |m| wgpu.wgpuShaderModuleAddRef(m);
    if (job.build.frag_state.module) |m| wgpu.wgpuShaderModuleAddRef(m);
    const task = sched.dispatch.?(sched, runAsyncCompileJob, job);
    s.pending_compiles[s.pending_compiles_count] = task;
    s.pending_compiles_count += 1;
}

fn flushPipelineCompiles(dev: [*c]ke.ke_gpu_device) callconv(.c) void {
    const s = state(dev);
    const sched = s.scheduler orelse return;
    var i: u32 = 0;
    while (i < s.pending_compiles_count) : (i += 1) {
        _ = sched.wait.?(sched, s.pending_compiles[i].?, null);
    }
    s.pending_compiles_count = 0;
}

fn createComputePipeline(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_compute_pipeline_params) callconv(.c) ke.ke_gpu_pipeline {
    const pp = @as(*const ke.ke_gpu_compute_pipeline_params, @ptrCast(p));

    var pipeline_layout: wgpu.WGPUPipelineLayout = null;
    if (pp.bind_group_layout_count > 0) {
        var bgl_handles: [4]wgpu.WGPUBindGroupLayout = undefined;
        const bgl_count = @min(pp.bind_group_layout_count, bgl_handles.len);
        for (0..bgl_count) |i| bgl_handles[i] = @ptrFromInt(pp.bind_group_layouts[i]);
        const layout_desc = wgpu.WGPUPipelineLayoutDescriptor{
            .nextInChain          = null,
            .label                = .{ .data = null, .length = 0 },
            .bindGroupLayoutCount = bgl_count,
            .bindGroupLayouts     = &bgl_handles,
        };
        pipeline_layout = wgpu.wgpuDeviceCreatePipelineLayout(state(dev).device, &layout_desc);
    }
    defer if (pipeline_layout != null) wgpu.wgpuPipelineLayoutRelease(pipeline_layout);

    const desc = wgpu.WGPUComputePipelineDescriptor{
        .nextInChain = null,
        .label       = .{ .data = null, .length = 0 },
        .layout      = pipeline_layout,
        .compute     = .{
            .nextInChain   = null,
            .module        = @ptrFromInt(pp.compute_module),
            .entryPoint    = .{ .data = if (pp.compute_entry != null) pp.compute_entry else "main", .length = wgpu.WGPU_STRLEN },
            .constantCount = 0,
            .constants     = null,
        },
    };
    return @intFromPtr(wgpu.wgpuDeviceCreateComputePipeline(state(dev).device, &desc));
}

fn createBindGroupLayout(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_bind_group_layout_params) callconv(.c) ke.ke_gpu_bind_group_layout {
    const pp = @as(*const ke.ke_gpu_bind_group_layout_params, @ptrCast(p));
    const n = @min(pp.entry_count, 32);
    var entries: [32]wgpu.WGPUBindGroupLayoutEntry = undefined;
    for (0..n) |i| {
        const src = @as(*const ke.ke_gpu_bind_group_layout_entry, @ptrCast(&pp.entries[i]));
        entries[i] = std.mem.zeroes(wgpu.WGPUBindGroupLayoutEntry);
        entries[i].binding    = src.binding;
        entries[i].visibility = mapShaderStage(src.visibility);
        switch (src.type) {
            ke.KE_GPU_BINDING_TYPE_BUFFER => {
                entries[i].buffer.type             = wgpu.WGPUBufferBindingType_Uniform;
                entries[i].buffer.hasDynamicOffset = if (src.has_dynamic_offset != 0) 1 else 0;
                entries[i].buffer.minBindingSize   = 0;
            },
            ke.KE_GPU_BINDING_TYPE_STORAGE_BUFFER => {
                entries[i].buffer.type             = wgpu.WGPUBufferBindingType_Storage;
                entries[i].buffer.hasDynamicOffset = if (src.has_dynamic_offset != 0) 1 else 0;
                entries[i].buffer.minBindingSize   = 0;
            },
            ke.KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER => {
                entries[i].buffer.type             = wgpu.WGPUBufferBindingType_ReadOnlyStorage;
                entries[i].buffer.hasDynamicOffset = if (src.has_dynamic_offset != 0) 1 else 0;
                entries[i].buffer.minBindingSize   = 0;
            },
            ke.KE_GPU_BINDING_TYPE_SAMPLER => {
                entries[i].sampler.type = wgpu.WGPUSamplerBindingType_Filtering;
            },
            ke.KE_GPU_BINDING_TYPE_TEXTURE => {
                entries[i].texture.sampleType    = wgpu.WGPUTextureSampleType_Float;
                entries[i].texture.viewDimension = if (src.view_dimension == ke.KE_GPU_TEXTURE_DIM_CUBE)
                    wgpu.WGPUTextureViewDimension_Cube
                else
                    wgpu.WGPUTextureViewDimension_2D;
                entries[i].texture.multisampled  = 0;
            },
            ke.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE => {
                entries[i].texture.sampleType    = wgpu.WGPUTextureSampleType_UnfilterableFloat;
                entries[i].texture.viewDimension = wgpu.WGPUTextureViewDimension_2D;
                entries[i].texture.multisampled  = 0;
            },
            ke.KE_GPU_BINDING_TYPE_STORAGE_TEXTURE => {
                entries[i].storageTexture.access        = wgpu.WGPUStorageTextureAccess_WriteOnly;
                entries[i].storageTexture.format        = wgpu.WGPUTextureFormat_RGBA8Unorm;
                entries[i].storageTexture.viewDimension = wgpu.WGPUTextureViewDimension_2D;
            },
            else => {},
        }
    }
    const desc = wgpu.WGPUBindGroupLayoutDescriptor{
        .nextInChain = null,
        .label       = .{ .data = null, .length = 0 },
        .entryCount  = n,
        .entries     = if (n > 0) &entries else null,
    };
    return @intFromPtr(wgpu.wgpuDeviceCreateBindGroupLayout(state(dev).device, &desc));
}

fn createBindGroup(dev: [*c]ke.ke_gpu_device, p: [*c]const ke.ke_gpu_bind_group_params, out_error: ?*?*ke.ke_error) callconv(.c) ke.ke_gpu_bind_group {
    const pp = @as(*const ke.ke_gpu_bind_group_params, @ptrCast(p));
    const n = @min(pp.entry_count, 32);
    var entries: [32]wgpu.WGPUBindGroupEntry = undefined;
    for (0..n) |i| {
        const src = @as(*const ke.ke_gpu_bind_group_entry, @ptrCast(&pp.entries[i]));
        entries[i] = std.mem.zeroes(wgpu.WGPUBindGroupEntry);
        entries[i].binding = src.binding;
        switch (src.type) {
            ke.KE_GPU_BINDING_TYPE_BUFFER,
            ke.KE_GPU_BINDING_TYPE_STORAGE_BUFFER,
            ke.KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER => {
                entries[i].buffer = @ptrFromInt(src.buffer);
                entries[i].offset = src.buffer_offset;
                entries[i].size   = src.buffer_size;
            },
            ke.KE_GPU_BINDING_TYPE_SAMPLER => {
                entries[i].sampler = @ptrFromInt(src.sampler);
            },
            ke.KE_GPU_BINDING_TYPE_TEXTURE,
            ke.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE,
            ke.KE_GPU_BINDING_TYPE_STORAGE_TEXTURE => {
                entries[i].textureView = @ptrFromInt(src.texture_view);
            },
            else => {},
        }
    }
    const desc = wgpu.WGPUBindGroupDescriptor{
        .nextInChain = null,
        .label       = .{ .data = null, .length = 0 },
        .layout      = @ptrFromInt(pp.layout),
        .entryCount  = n,
        .entries     = if (n > 0) &entries else null,
    };
    const s = state(dev);

    wgpu.wgpuDevicePushErrorScope(s.device, wgpu.WGPUErrorFilter_Validation);
    const bg: wgpu.WGPUBindGroup = wgpu.wgpuDeviceCreateBindGroup(s.device, &desc);
    var se = ScopeError{ .captured = false, .buf = undefined };
    _ = wgpu.wgpuDevicePopErrorScope(s.device, .{
        .nextInChain = null,
        .mode      = wgpu.WGPUCallbackMode_AllowSpontaneous,
        .callback  = popErrorCallback,
        .userdata1 = &se,
        .userdata2 = null,
    });
    _ = wgpu.wgpuDevicePoll(s.device, 1, null);

    if (se.captured) {
        ke.ke_error_set(out_error, &KE_ERROR_WGPU_RESOURCE_CREATION, &se.buf, @src().file, @intCast(@src().line), null);
        if (bg != null) wgpu.wgpuBindGroupRelease(bg);
        return ke.KE_GPU_INVALID_HANDLE;
    }
    return @intFromPtr(bg orelse return ke.KE_GPU_INVALID_HANDLE);
}

fn destroyBuffer(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_buffer) callconv(.c) void {
    wgpu.wgpuBufferDestroy(@ptrFromInt(h));
    wgpu.wgpuBufferRelease(@ptrFromInt(h));
}
fn destroyTexture(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_texture) callconv(.c) void {
    wgpu.wgpuTextureDestroy(@ptrFromInt(h));
    wgpu.wgpuTextureRelease(@ptrFromInt(h));
}
fn destroyTextureView(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_texture_view) callconv(.c) void { wgpu.wgpuTextureViewRelease(@ptrFromInt(h)); }
fn destroySampler(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_sampler) callconv(.c) void { wgpu.wgpuSamplerRelease(@ptrFromInt(h)); }
fn destroyShaderModule(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_shader_module) callconv(.c) void { wgpu.wgpuShaderModuleRelease(@ptrFromInt(h)); }
fn destroyPipeline(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_pipeline) callconv(.c) void { wgpu.wgpuRenderPipelineRelease(@ptrFromInt(h)); }
fn destroyComputePipeline(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_pipeline) callconv(.c) void { wgpu.wgpuComputePipelineRelease(@ptrFromInt(h)); }
fn destroyBindGroupLayout(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_bind_group_layout) callconv(.c) void { wgpu.wgpuBindGroupLayoutRelease(@ptrFromInt(h)); }
fn destroyBindGroup(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_bind_group) callconv(.c) void { wgpu.wgpuBindGroupRelease(@ptrFromInt(h)); }

fn rpSetPipeline(rp: [*c]ke.ke_gpu_render_pass, pipe: ke.ke_gpu_pipeline) callconv(.c) void {
    wgpu.wgpuRenderPassEncoderSetPipeline(@ptrCast(rp.*.handle), @ptrFromInt(pipe));
}
fn rpSetBindGroup(rp: [*c]ke.ke_gpu_render_pass, group_index: u32, bg: ke.ke_gpu_bind_group, dynamic_offsets: [*c]const u32, dyn_count: u32) callconv(.c) void {
    wgpu.wgpuRenderPassEncoderSetBindGroup(@ptrCast(rp.*.handle), group_index, @ptrFromInt(bg), dyn_count, dynamic_offsets);
}
fn rpSetVertexBuffer(rp: [*c]ke.ke_gpu_render_pass, slot: u32, b: ke.ke_gpu_buffer, offset: usize) callconv(.c) void {
    wgpu.wgpuRenderPassEncoderSetVertexBuffer(@ptrCast(rp.*.handle), slot, @ptrFromInt(b), offset, wgpu.WGPU_WHOLE_SIZE);
}
fn rpSetIndexBuffer(rp: [*c]ke.ke_gpu_render_pass, b: ke.ke_gpu_buffer, fmt: ke.ke_gpu_index_format, offset: usize) callconv(.c) void {
    const wfmt: wgpu.WGPUIndexFormat = switch (fmt) {
        ke.KE_GPU_INDEX_FORMAT_UINT16 => wgpu.WGPUIndexFormat_Uint16,
        ke.KE_GPU_INDEX_FORMAT_UINT32 => wgpu.WGPUIndexFormat_Uint32,
        else => wgpu.WGPUIndexFormat_Undefined,
    };
    wgpu.wgpuRenderPassEncoderSetIndexBuffer(@ptrCast(rp.*.handle), @ptrFromInt(b), wfmt, offset, wgpu.WGPU_WHOLE_SIZE);
}
fn rpSetViewport(rp: [*c]ke.ke_gpu_render_pass, x: f32, y: f32, w: f32, h: f32, min_d: f32, max_d: f32) callconv(.c) void {
    wgpu.wgpuRenderPassEncoderSetViewport(@ptrCast(rp.*.handle), x, y, w, h, min_d, max_d);
}
fn rpSetScissor(rp: [*c]ke.ke_gpu_render_pass, x: i32, y: i32, w: u32, h: u32) callconv(.c) void {
    wgpu.wgpuRenderPassEncoderSetScissorRect(@ptrCast(rp.*.handle), @intCast(x), @intCast(y), w, h);
}
fn rpDraw(rp: [*c]ke.ke_gpu_render_pass, vert_count: u32, inst_count: u32, first_vert: u32, first_inst: u32) callconv(.c) void {
    wgpu.wgpuRenderPassEncoderDraw(@ptrCast(rp.*.handle), vert_count, inst_count, first_vert, first_inst);
}
fn rpDrawIndexed(rp: [*c]ke.ke_gpu_render_pass, idx_count: u32, inst_count: u32, first_idx: u32, base_vert: i32, first_inst: u32) callconv(.c) void {
    wgpu.wgpuRenderPassEncoderDrawIndexed(@ptrCast(rp.*.handle), idx_count, inst_count, first_idx, base_vert, first_inst);
}
fn rpDrawIndirect(rp: [*c]ke.ke_gpu_render_pass, indirect_buf: ke.ke_gpu_buffer, offset: usize) callconv(.c) void {
    wgpu.wgpuRenderPassEncoderDrawIndirect(@ptrCast(rp.*.handle), @ptrFromInt(indirect_buf), offset);
}
fn rpEnd(rp: [*c]ke.ke_gpu_render_pass) callconv(.c) void {
    wgpu.wgpuRenderPassEncoderEnd(@ptrCast(rp.*.handle));
    wgpu.wgpuRenderPassEncoderRelease(@ptrCast(rp.*.handle));
    gpa.destroy(@as(*ke.ke_gpu_render_pass, @ptrCast(rp)));
}

fn cpSetPipeline(cp: [*c]ke.ke_gpu_compute_pass, pipe: ke.ke_gpu_pipeline) callconv(.c) void {
    wgpu.wgpuComputePassEncoderSetPipeline(@ptrCast(cp.*.handle), @ptrFromInt(pipe));
}
fn cpSetBindGroup(cp: [*c]ke.ke_gpu_compute_pass, group_index: u32, bg: ke.ke_gpu_bind_group, dynamic_offsets: [*c]const u32, dyn_count: u32) callconv(.c) void {
    wgpu.wgpuComputePassEncoderSetBindGroup(@ptrCast(cp.*.handle), group_index, @ptrFromInt(bg), dyn_count, dynamic_offsets);
}
fn cpDispatch(cp: [*c]ke.ke_gpu_compute_pass, x: u32, y: u32, z: u32) callconv(.c) void {
    wgpu.wgpuComputePassEncoderDispatchWorkgroups(@ptrCast(cp.*.handle), x, y, z);
}
fn cpDispatchIndirect(cp: [*c]ke.ke_gpu_compute_pass, indirect_buf: ke.ke_gpu_buffer, offset: usize) callconv(.c) void {
    wgpu.wgpuComputePassEncoderDispatchWorkgroupsIndirect(@ptrCast(cp.*.handle), @ptrFromInt(indirect_buf), offset);
}
fn cpEnd(cp: [*c]ke.ke_gpu_compute_pass) callconv(.c) void {
    wgpu.wgpuComputePassEncoderEnd(@ptrCast(cp.*.handle));
    wgpu.wgpuComputePassEncoderRelease(@ptrCast(cp.*.handle));
    gpa.destroy(@as(*ke.ke_gpu_compute_pass, @ptrCast(cp)));
}

fn cmdBufDestroy(cmd: [*c]ke.ke_gpu_command_buffer) callconv(.c) void {
    wgpu.wgpuCommandBufferRelease(@ptrCast(cmd.*.handle));
    gpa.destroy(@as(*ke.ke_gpu_command_buffer, @ptrCast(cmd)));
}

fn encBeginRenderPass(enc: [*c]ke.ke_gpu_command_encoder, p: [*c]const ke.ke_gpu_render_pass_params) callconv(.c) [*c]ke.ke_gpu_render_pass {
    const pp = @as(*const ke.ke_gpu_render_pass_params, @ptrCast(p));

    var color_attachments: [8]wgpu.WGPURenderPassColorAttachment = undefined;
    const color_count = @min(pp.color_attachment_count, color_attachments.len);
    for (0..color_count) |i| {
        const ca = @as(*const ke.ke_gpu_color_attachment, @ptrCast(&pp.color_attachments[i]));
        color_attachments[i] = .{
            .nextInChain   = null,
            .view          = @ptrFromInt(ca.view),
            .depthSlice    = wgpu.WGPU_DEPTH_SLICE_UNDEFINED,
            .resolveTarget = null,
            .loadOp        = toWgpuLoadOp(ca.load_op),
            .storeOp       = toWgpuStoreOp(ca.store_op),
            .clearValue    = .{ .r = ca.clear_value.color[0], .g = ca.clear_value.color[1], .b = ca.clear_value.color[2], .a = ca.clear_value.color[3] },
        };
    }

    var ds_attach: wgpu.WGPURenderPassDepthStencilAttachment = undefined;
    const has_ds = pp.depth_stencil_attachment != null;
    if (has_ds) {
        const dsa = @as(*const ke.ke_gpu_depth_stencil_attachment, @ptrCast(pp.depth_stencil_attachment));
        const depth_ro = dsa.depth_read_only != 0;
        ds_attach = .{
            .view              = @ptrFromInt(dsa.view),
            .depthLoadOp       = if (depth_ro) wgpu.WGPULoadOp_Undefined else toWgpuLoadOp(dsa.depth_load_op),
            .depthStoreOp      = if (depth_ro) wgpu.WGPUStoreOp_Undefined else toWgpuStoreOp(dsa.depth_store_op),
            .depthClearValue   = dsa.clear_depth,
            .depthReadOnly     = if (depth_ro) 1 else 0,
            .stencilLoadOp     = wgpu.WGPULoadOp_Undefined,
            .stencilStoreOp    = toWgpuStoreOp(dsa.stencil_store_op),
            .stencilClearValue = dsa.clear_stencil,
            .stencilReadOnly   = if (dsa.stencil_read_only != 0) 1 else 0,
        };
    }

    const rp_desc = wgpu.WGPURenderPassDescriptor{
        .nextInChain            = null,
        .label                  = .{ .data = null, .length = 0 },
        .colorAttachmentCount   = color_count,
        .colorAttachments       = if (color_count > 0) &color_attachments else null,
        .depthStencilAttachment = if (has_ds) &ds_attach else null,
        .occlusionQuerySet      = null,
        .timestampWrites        = null,
    };

    const raw = wgpu.wgpuCommandEncoderBeginRenderPass(@ptrCast(enc.*.handle), &rp_desc) orelse return null;
    const rp = gpa.create(ke.ke_gpu_render_pass) catch return null;
    rp.* = .{
        .handle            = raw,
        .device            = enc.*.device,
        .set_pipeline      = rpSetPipeline,
        .set_bind_group    = rpSetBindGroup,
        .set_vertex_buffer = rpSetVertexBuffer,
        .set_index_buffer  = rpSetIndexBuffer,
        .set_viewport      = rpSetViewport,
        .set_scissor       = rpSetScissor,
        .draw              = rpDraw,
        .draw_indexed      = rpDrawIndexed,
        .draw_indirect     = rpDrawIndirect,
        .end               = rpEnd,
    };
    return rp;
}

fn encBeginComputePass(enc: [*c]ke.ke_gpu_command_encoder) callconv(.c) [*c]ke.ke_gpu_compute_pass {
    const desc = wgpu.WGPUComputePassDescriptor{ .nextInChain = null, .label = .{ .data = null, .length = 0 }, .timestampWrites = null };
    const raw = wgpu.wgpuCommandEncoderBeginComputePass(@ptrCast(enc.*.handle), &desc) orelse return null;
    const cp = gpa.create(ke.ke_gpu_compute_pass) catch return null;
    cp.* = .{
        .handle            = raw,
        .device            = enc.*.device,
        .set_pipeline      = cpSetPipeline,
        .set_bind_group    = cpSetBindGroup,
        .dispatch          = cpDispatch,
        .dispatch_indirect = cpDispatchIndirect,
        .end               = cpEnd,
    };
    return cp;
}

fn encPipelineBarrier(_: [*c]ke.ke_gpu_command_encoder, _: [*c]const ke.ke_gpu_barrier) callconv(.c) void {}

fn encCopyBufferToBuffer(enc: [*c]ke.ke_gpu_command_encoder, src: ke.ke_gpu_buffer, src_off: usize, dst: ke.ke_gpu_buffer, dst_off: usize, size: usize) callconv(.c) void {
    wgpu.wgpuCommandEncoderCopyBufferToBuffer(@ptrCast(enc.*.handle), @ptrFromInt(src), src_off, @ptrFromInt(dst), dst_off, size);
}

fn rowPitchValid(bytes_per_row: u32, out_error: ?*?*ke.ke_error, src: std.builtin.SourceLocation) bool {
    if (bytes_per_row % copy_row_alignment == 0) return true;
    ke.ke_error_set(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "bytes_per_row is not a multiple of the copy row alignment", src.file, @intCast(src.line), null);
    return false;
}

fn encCopyBufferToTexture(enc: [*c]ke.ke_gpu_command_encoder, src: ke.ke_gpu_buffer, src_off: usize, bytes_per_row: u32, dst: ke.ke_gpu_texture, x: u32, y: u32, z: u32, width: u32, height: u32, out_error: ?*?*ke.ke_error) callconv(.c) bool {
    if (!rowPitchValid(bytes_per_row, out_error, @src())) return false;
    const src_info = wgpu.WGPUTexelCopyBufferInfo{
        .layout = .{ .offset = src_off, .bytesPerRow = bytes_per_row, .rowsPerImage = height },
        .buffer = @ptrFromInt(src),
    };
    const dst_info = wgpu.WGPUTexelCopyTextureInfo{
        .texture = @ptrFromInt(dst),
        .mipLevel = 0,
        .origin = .{ .x = x, .y = y, .z = z },
        .aspect = wgpu.WGPUTextureAspect_All,
    };
    const extent = wgpu.WGPUExtent3D{ .width = width, .height = height, .depthOrArrayLayers = 1 };
    wgpu.wgpuCommandEncoderCopyBufferToTexture(@ptrCast(enc.*.handle), &src_info, &dst_info, &extent);
    return true;
}

fn encCopyTextureToBuffer(enc: [*c]ke.ke_gpu_command_encoder, src: ke.ke_gpu_texture, x: u32, y: u32, z: u32, dst: ke.ke_gpu_buffer, dst_off: usize, bytes_per_row: u32, width: u32, height: u32, out_error: ?*?*ke.ke_error) callconv(.c) bool {
    if (!rowPitchValid(bytes_per_row, out_error, @src())) return false;
    const src_info = wgpu.WGPUTexelCopyTextureInfo{
        .texture = @ptrFromInt(src),
        .mipLevel = 0,
        .origin = .{ .x = x, .y = y, .z = z },
        .aspect = wgpu.WGPUTextureAspect_All,
    };
    const dst_info = wgpu.WGPUTexelCopyBufferInfo{
        .layout = .{ .offset = dst_off, .bytesPerRow = bytes_per_row, .rowsPerImage = height },
        .buffer = @ptrFromInt(dst),
    };
    const extent = wgpu.WGPUExtent3D{ .width = width, .height = height, .depthOrArrayLayers = 1 };
    wgpu.wgpuCommandEncoderCopyTextureToBuffer(@ptrCast(enc.*.handle), &src_info, &dst_info, &extent);
    return true;
}

fn encCopyTextureToTexture(enc: [*c]ke.ke_gpu_command_encoder, src: ke.ke_gpu_texture, dst: ke.ke_gpu_texture, width: u32, height: u32) callconv(.c) void {
    const src_info = wgpu.WGPUTexelCopyTextureInfo{
        .texture = @ptrFromInt(src),
        .mipLevel = 0,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
        .aspect = wgpu.WGPUTextureAspect_All,
    };
    const dst_info = wgpu.WGPUTexelCopyTextureInfo{
        .texture = @ptrFromInt(dst),
        .mipLevel = 0,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
        .aspect = wgpu.WGPUTextureAspect_All,
    };
    const extent = wgpu.WGPUExtent3D{ .width = width, .height = height, .depthOrArrayLayers = 1 };
    wgpu.wgpuCommandEncoderCopyTextureToTexture(@ptrCast(enc.*.handle), &src_info, &dst_info, &extent);
}

fn encFinish(enc: [*c]ke.ke_gpu_command_encoder) callconv(.c) [*c]ke.ke_gpu_command_buffer {
    const desc = wgpu.WGPUCommandBufferDescriptor{ .nextInChain = null, .label = .{ .data = null, .length = 0 } };
    const raw = wgpu.wgpuCommandEncoderFinish(@ptrCast(enc.*.handle), &desc) orelse return null;
    const cmd = gpa.create(ke.ke_gpu_command_buffer) catch return null;
    cmd.* = .{ .handle = raw, .device = enc.*.device, .destroy = cmdBufDestroy };
    return cmd;
}

fn encDestroy(enc: [*c]ke.ke_gpu_command_encoder) callconv(.c) void {
    wgpu.wgpuCommandEncoderRelease(@ptrCast(enc.*.handle));
    gpa.destroy(@as(*ke.ke_gpu_command_encoder, @ptrCast(enc)));
}

fn createCommandEncoder(dev: [*c]ke.ke_gpu_device) callconv(.c) [*c]ke.ke_gpu_command_encoder {
    const desc = wgpu.WGPUCommandEncoderDescriptor{ .nextInChain = null, .label = .{ .data = null, .length = 0 } };
    const raw = wgpu.wgpuDeviceCreateCommandEncoder(state(dev).device, &desc) orelse return null;
    const enc = gpa.create(ke.ke_gpu_command_encoder) catch return null;
    enc.* = .{
        .handle                 = raw,
        .device                 = dev,
        .begin_render_pass      = encBeginRenderPass,
        .begin_compute_pass     = encBeginComputePass,
        .pipeline_barrier       = encPipelineBarrier,
        .copy_buffer_to_buffer  = encCopyBufferToBuffer,
        .copy_buffer_to_texture = encCopyBufferToTexture,
        .copy_texture_to_texture = encCopyTextureToTexture,
        .copy_texture_to_buffer = encCopyTextureToBuffer,
        .finish                 = encFinish,
        .destroy                = encDestroy,
    };
    return enc;
}

fn writeBuffer(dev: [*c]ke.ke_gpu_device, h: ke.ke_gpu_buffer, offset: u64, data: ?*const anyopaque, size: usize) callconv(.c) void {
    wgpu.wgpuQueueWriteBuffer(state(dev).queue, @ptrFromInt(h), offset, data, size);
}

fn mapBuffer(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_buffer, offset: usize, size: usize) callconv(.c) ?*anyopaque {
    const buffer: wgpu.WGPUBuffer = @ptrFromInt(h);
    if (wgpu.wgpuBufferGetMappedRange(buffer, offset, size)) |range| return range;
    return @constCast(wgpu.wgpuBufferGetConstMappedRange(buffer, offset, size));
}

const MapReadRequest = struct {
    buffer: ke.ke_gpu_buffer,
    on_ready: *const fn (ke.ke_gpu_buffer, bool, ?*anyopaque) callconv(.c) void,
    user: ?*anyopaque,
};

fn mapReadDone(status: wgpu.WGPUMapAsyncStatus, _: wgpu.WGPUStringView, userdata1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const req: *MapReadRequest = @ptrCast(@alignCast(userdata1.?));
    req.on_ready(req.buffer, status == wgpu.WGPUMapAsyncStatus_Success, req.user);
    gpa.destroy(req);
}

fn mapBufferRead(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_buffer, offset: usize, size: usize,
                 on_ready: ?*const fn (ke.ke_gpu_buffer, bool, ?*anyopaque) callconv(.c) void, user: ?*anyopaque) callconv(.c) void {
    const cb = on_ready orelse return;
    const req = gpa.create(MapReadRequest) catch {
        cb(h, false, user);
        return;
    };
    req.* = .{ .buffer = h, .on_ready = cb, .user = user };
    _ = wgpu.wgpuBufferMapAsync(@ptrFromInt(h), wgpu.WGPUMapMode_Read, offset, size, .{
        .nextInChain = null,
        .mode = wgpu.WGPUCallbackMode_AllowProcessEvents,
        .callback = mapReadDone,
        .userdata1 = req,
        .userdata2 = null,
    });
}
fn mapBufferWrite(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_buffer, offset: usize, size: usize) callconv(.c) ?*anyopaque {
    return wgpu.wgpuBufferGetMappedRange(@ptrFromInt(h), offset, size);
}
fn unmapBuffer(_: [*c]ke.ke_gpu_device, h: ke.ke_gpu_buffer) callconv(.c) void {
    wgpu.wgpuBufferUnmap(@ptrFromInt(h));
}

fn getCapabilities(dev: [*c]ke.ke_gpu_device, out: [*c]ke.ke_gpu_capabilities) callconv(.c) void {
    const p = @as(*ke.ke_gpu_capabilities, @ptrCast(out));
    p.* = std.mem.zeroes(ke.ke_gpu_capabilities);

    var limits: wgpu.WGPULimits = std.mem.zeroes(wgpu.WGPULimits);
    const status = wgpu.wgpuAdapterGetLimits(state(dev).adapter, &limits);
    if (status != wgpu.WGPUStatus_Success) return;

    p.max_texture_dimension_2d     = limits.maxTextureDimension2D;
    p.max_texture_array_layers     = limits.maxTextureArrayLayers;
    p.max_bind_groups              = limits.maxBindGroups;
    p.max_vertex_attributes        = limits.maxVertexAttributes;
    p.max_vertex_buffers           = limits.maxVertexBuffers;
    p.max_uniform_buffer_size      = @truncate(limits.maxUniformBufferBindingSize);
    p.max_storage_buffer_size      = @truncate(limits.maxStorageBufferBindingSize);
    p.max_compute_workgroup_size_x = limits.maxComputeWorkgroupSizeX;
    p.max_compute_workgroup_size_y = limits.maxComputeWorkgroupSizeY;
    p.max_compute_workgroup_size_z = limits.maxComputeWorkgroupSizeZ;
    p.copy_bytes_per_row_alignment = copy_row_alignment;
}

fn queryExtension(_: [*c]ke.ke_gpu_device, _: [*c]const u8) callconv(.c) ?*const anyopaque {
    return null;
}

test "creating the device and destroying it, or failing to create it, leaves no block allocated" {
    const handle = ke_gpu_device_webgpu_create(null, null);
    if (handle.ref != null) handle.destroy.?(handle.ref);
    try heap.expectNoLeaks();
}

const ReadbackProbe = struct {
    fired: bool = false,
    ok: bool = false,
};

fn readbackProbeDone(_: ke.ke_gpu_buffer, ok: bool, user: ?*anyopaque) callconv(.c) void {
    const probe: *ReadbackProbe = @ptrCast(@alignCast(user.?));
    probe.fired = true;
    probe.ok = ok;
}

test "a texture's pixels are read back through a copy to a buffer and an asynchronous map" {
    const handle = ke_gpu_device_webgpu_create(null, null);
    if (handle.ref == null) return error.SkipZigTest;
    defer handle.destroy.?(handle.ref);
    const dev = handle.ref;

    const width: u32 = 64;
    const height: u32 = 4;
    const row_bytes: u32 = width * 4;
    var pixels: [row_bytes * height]u8 = undefined;
    for (&pixels, 0..) |*b, i| b.* = @truncate(i *% 7);

    const tex = dev.*.create_texture.?(dev, &ke.ke_gpu_texture_params{
        .width = width,
        .height = height,
        .depth_or_array_layers = 1,
        .format = ke.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = ke.KE_GPU_TEXTURE_DIM_2D,
        .usage = ke.KE_GPU_TEXTURE_USAGE_COPY_SRC,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = &pixels,
        .initial_data_size = pixels.len,
    });
    try std.testing.expect(tex != ke.KE_GPU_INVALID_HANDLE);
    defer dev.*.destroy_texture.?(dev, tex);

    const buf = dev.*.create_buffer.?(dev, &ke.ke_gpu_buffer_params{
        .initial_data = null,
        .size = row_bytes * height,
        .usage = ke.KE_GPU_BUFFER_USAGE_MAP_READ | ke.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, null);
    try std.testing.expect(buf != ke.KE_GPU_INVALID_HANDLE);
    defer dev.*.destroy_buffer.?(dev, buf);

    const enc = dev.*.create_command_encoder.?(dev);
    defer enc.*.destroy.?(enc);

    var misaligned: ?*ke.ke_error = null;
    try std.testing.expect(!enc.*.copy_texture_to_buffer.?(enc, tex, 0, 0, 0, buf, 0, row_bytes - 1, width, height, &misaligned));
    try std.testing.expect(misaligned != null);
    try std.testing.expect(ke.ke_error_is(misaligned, &ke.KE_ERROR_INVALID_ARGUMENT));

    try std.testing.expect(enc.*.copy_texture_to_buffer.?(enc, tex, 0, 0, 0, buf, 0, row_bytes, width, height, null));
    const cmd = enc.*.finish.?(enc);
    var cmds = [_][*c]ke.ke_gpu_command_buffer{cmd};
    const queue = dev.*.get_default_queue.?(dev);
    dev.*.queue_submit.?(dev, queue, &cmds, 1);

    var probe = ReadbackProbe{};
    dev.*.map_buffer_read.?(dev, buf, 0, row_bytes * height, readbackProbeDone, &probe);
    dev.*.queue_wait_idle.?(dev, queue);
    try std.testing.expect(probe.fired);
    try std.testing.expect(probe.ok);

    const mapped: [*]const u8 = @ptrCast(dev.*.map_buffer.?(dev, buf, 0, row_bytes * height).?);
    try std.testing.expectEqualSlices(u8, &pixels, mapped[0..pixels.len]);
    dev.*.unmap_buffer.?(dev, buf);
}

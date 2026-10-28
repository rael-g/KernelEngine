//! Fakes of the engine contracts that render and framework code is written against, for unit
//! tests that run with no GPU, window or ecs.

const std = @import("std");
const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");

/// Fake of the GPU device contract. `api` returns the vtable pointer and is valid only
/// after `init`. `live` counts the handles minted and not released, `compute_live` counts
/// the compute pipelines among them, and `fallible_created` against `fallible_budget` is
/// the only way a creation is refused. A refused creation fails as general, writes no
/// handle and leaves every counter as it was. Command
/// recording keeps no history: one record per kind of pass is handed back, and only the
/// latest label and the depth of open debug groups are kept.
pub const Device = struct {
    vtable: abi_render.ke_gpu_device,
    next: u64,
    live: i64,
    compute_live: i64,
    fallible_created: u32,
    fallible_budget: u32,
    encoder: abi_render.ke_gpu_command_encoder,
    render_pass: abi_render.ke_gpu_render_pass,
    compute_pass: abi_render.ke_gpu_compute_pass,
    command_buffer: abi_render.ke_gpu_command_buffer,
    texture_label: [*c]const u8,
    texture_view_label: [*c]const u8,
    render_pass_label: [*c]const u8,
    render_passes: u32,
    submitted: u32,
    color_load: abi_render.ke_gpu_load_op,
    depth_load: ?abi_render.ke_gpu_load_op,
    compute_pass_label: [*c]const u8,
    debug_group_label: [*c]const u8,
    debug_groups_open: i32,
    buffer_writes: u32,
    bytes_written: usize,

    pub fn init(self: *Device) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_gpu_device), .next = 1, .live = 0, .compute_live = 0, .fallible_created = 0, .fallible_budget = std.math.maxInt(u32), .encoder = undefined, .render_pass = undefined, .compute_pass = undefined, .command_buffer = undefined, .texture_label = null, .texture_view_label = null, .render_pass_label = null, .render_passes = 0, .submitted = 0, .color_load = 0, .depth_load = null, .compute_pass_label = null, .debug_group_label = null, .debug_groups_open = 0, .buffer_writes = 0, .bytes_written = 0 };
        self.vtable.handle = self;
        self.vtable.create_buffer = &createBuffer;
        self.vtable.create_bind_group_layout = &createBindGroupLayout;
        self.vtable.create_bind_group = &createBindGroup;
        self.vtable.create_compute_pipeline = &createComputePipeline;
        self.vtable.create_render_pipeline = &createRenderPipeline;
        self.vtable.create_sampler = &createSampler;
        self.vtable.destroy_buffer = &destroyHandle;
        self.vtable.destroy_bind_group_layout = &destroyHandle;
        self.vtable.destroy_bind_group = &destroyHandle;
        self.vtable.destroy_pipeline = &destroyHandle;
        self.vtable.destroy_compute_pipeline = &destroyComputePipeline;
        self.vtable.destroy_sampler = &destroyHandle;
        self.vtable.create_texture = &createTexture;
        self.vtable.create_texture_view = &createTextureView;
        self.vtable.destroy_texture = &destroyHandle;
        self.vtable.destroy_texture_view = &destroyHandle;
        self.vtable.write_buffer = &writeBuffer;
        self.vtable.get_default_queue = &defaultQueue;
        self.vtable.query_extension = &queryExtension;
        self.vtable.get_ndc_convention = &ndcConvention;
        self.vtable.shader_language = &shaderLanguage;
        self.vtable.create_shader_module = &createShaderModule;
        self.vtable.destroy_shader_module = &destroyHandle;
        self.vtable.create_render_pipeline_async = &createRenderPipelineAsync;
        self.vtable.create_command_encoder = &createCommandEncoder;
        self.vtable.queue_submit = &queueSubmit;
        self.vtable.queue_poll = &queuePoll;
        self.encoder = std.mem.zeroes(abi_render.ke_gpu_command_encoder);
        self.encoder.handle = self;
        self.encoder.begin_render_pass = &beginRenderPass;
        self.encoder.begin_compute_pass = &beginComputePass;
        self.encoder.finish = &finishEncoder;
        self.render_pass = std.mem.zeroes(abi_render.ke_gpu_render_pass);
        self.render_pass.end = &endRenderPass;
        self.render_pass.set_pipeline = &setRenderPipeline;
        self.render_pass.draw = &drawRenderPass;
        self.compute_pass = std.mem.zeroes(abi_render.ke_gpu_compute_pass);
        self.compute_pass.handle = self;
        self.compute_pass.end = &endComputePass;
        self.compute_pass.push_debug_group = &pushDebugGroup;
        self.compute_pass.pop_debug_group = &popDebugGroup;
        self.command_buffer = std.mem.zeroes(abi_render.ke_gpu_command_buffer);
    }

    fn encoderOwner(enc: ?*abi_render.ke_gpu_command_encoder) *Device {
        return @ptrCast(@alignCast(enc.?.handle.?));
    }

    fn passOwner(pass: ?*abi_render.ke_gpu_compute_pass) *Device {
        return @ptrCast(@alignCast(pass.?.handle.?));
    }

    /// Every begin returns the same render pass record, so the label, the first color
    /// load and the depth's read-only flag of the latest begin replace the ones before it;
    /// `render_passes` counts the begins.
    fn beginRenderPass(enc: ?*abi_render.ke_gpu_command_encoder, p: [*c]const abi_render.ke_gpu_render_pass_params) callconv(.c) [*c]abi_render.ke_gpu_render_pass {
        const self = encoderOwner(enc);
        self.render_pass_label = p.*.label;
        self.render_passes += 1;
        self.color_load = if (p.*.color_attachment_count > 0) p.*.color_attachments.?[0].load_op else 0;
        self.depth_load = if (p.*.depth_stencil_attachment != null) p.*.depth_stencil_attachment.?.depth_load_op else null;
        return &self.render_pass;
    }

    /// Every begin returns the same compute pass record, so the label of the latest begin
    /// replaces the one before it.
    fn beginComputePass(enc: ?*abi_render.ke_gpu_command_encoder, p: [*c]const abi_render.ke_gpu_compute_pass_params) callconv(.c) [*c]abi_render.ke_gpu_compute_pass {
        const self = encoderOwner(enc);
        self.compute_pass_label = if (p != null) p.*.label else null;
        return &self.compute_pass;
    }

    fn endRenderPass(_: ?*abi_render.ke_gpu_render_pass) callconv(.c) void {}
    fn setRenderPipeline(_: ?*abi_render.ke_gpu_render_pass, _: abi_render.ke_gpu_pipeline) callconv(.c) void {}
    fn drawRenderPass(_: ?*abi_render.ke_gpu_render_pass, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}

    fn endComputePass(_: ?*abi_render.ke_gpu_compute_pass) callconv(.c) void {}

    fn pushDebugGroup(pass: ?*abi_render.ke_gpu_compute_pass, label: [*c]const u8) callconv(.c) void {
        const self = passOwner(pass);
        self.debug_group_label = label;
        self.debug_groups_open += 1;
    }

    /// Nothing pairs it with a push, so the depth can drop below zero.
    fn popDebugGroup(pass: ?*abi_render.ke_gpu_compute_pass) callconv(.c) void {
        passOwner(pass).debug_groups_open -= 1;
    }

    fn finishEncoder(enc: ?*abi_render.ke_gpu_command_encoder, out: [*c]abi_render.ke_gpu_command_buffer_handle) callconv(.c) abi_result.ke_result {
        out.* = .{ .ref = &encoderOwner(enc).command_buffer, .destroy = &destroyCommandBuffer };
        return abi_result.KE_OK;
    }

    fn destroyCommandBuffer(_: ?*abi_render.ke_gpu_command_buffer) callconv(.c) void {}

    fn createCommandEncoder(self: ?*abi_render.ke_gpu_device, _: [*c]const abi_render.ke_gpu_command_encoder_params, out: [*c]abi_render.ke_gpu_command_encoder_handle) callconv(.c) abi_result.ke_result {
        out.* = .{ .ref = &of(self).encoder, .destroy = &destroyEncoder };
        return abi_result.KE_OK;
    }

    fn destroyEncoder(_: ?*abi_render.ke_gpu_command_encoder) callconv(.c) void {}

    /// `submitted` counts the command buffers submitted.
    fn queueSubmit(self: ?*abi_render.ke_gpu_device, _: abi_render.ke_gpu_queue, _: [*c]const [*c]abi_render.ke_gpu_command_buffer, count: u32) callconv(.c) void {
        const d: *Device = @ptrCast(@alignCast(self.?.handle));
        d.submitted += count;
    }

    fn queuePoll(_: ?*abi_render.ke_gpu_device, _: abi_render.ke_gpu_queue) callconv(.c) void {}

    pub fn api(self: *Device) *abi_render.ke_gpu_device {
        return &self.vtable;
    }

    fn of(self: ?*abi_render.ke_gpu_device) *Device {
        return @ptrCast(@alignCast(self.?.handle));
    }

    /// Counts the handle in `live` and returns the value `next` held before this call. Both
    /// updates are atomic, so the device can mint from several threads at once.
    fn mint(self: ?*abi_render.ke_gpu_device) u64 {
        const d = of(self);
        _ = @atomicRmw(i64, &d.live, .Add, 1, .monotonic);
        return @atomicRmw(u64, &d.next, .Add, 1, .monotonic);
    }

    /// Called by the creations that can be refused, before they mint. Plain operations,
    /// unlike `mint`, so it is not safe to call from several threads at once.
    fn spendFallible(self: ?*abi_render.ke_gpu_device) bool {
        const d = of(self);
        if (d.fallible_created >= d.fallible_budget) return false;
        d.fallible_created += 1;
        return true;
    }

    /// Refused through `spendFallible`: once the budget is spent it fails as general and writes
    /// nothing.
    fn createBuffer(self: ?*abi_render.ke_gpu_device, _: [*c]const abi_render.ke_gpu_buffer_params, out: [*c]abi_render.ke_gpu_buffer) callconv(.c) abi_result.ke_result {
        if (!spendFallible(self)) return abi_result.KE_RESULT_GENERAL;
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    fn createBindGroupLayout(self: ?*abi_render.ke_gpu_device, _: [*c]const abi_render.ke_gpu_bind_group_layout_params, out: [*c]abi_render.ke_gpu_bind_group_layout) callconv(.c) abi_result.ke_result {
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    /// Refused through `spendFallible`: once the budget is spent it fails as general and writes
    /// nothing.
    fn createBindGroup(self: ?*abi_render.ke_gpu_device, _: [*c]const abi_render.ke_gpu_bind_group_params, out: [*c]abi_render.ke_gpu_bind_group) callconv(.c) abi_result.ke_result {
        if (!spendFallible(self)) return abi_result.KE_RESULT_GENERAL;
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    /// Also counts toward `compute_live`, which `destroyComputePipeline` releases.
    fn createComputePipeline(self: ?*abi_render.ke_gpu_device, _: [*c]const abi_render.ke_gpu_compute_pipeline_params, out: [*c]abi_render.ke_gpu_pipeline) callconv(.c) abi_result.ke_result {
        _ = @atomicRmw(i64, &of(self).compute_live, .Add, 1, .monotonic);
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    fn destroyComputePipeline(self: ?*abi_render.ke_gpu_device, h: abi_render.ke_gpu_pipeline) callconv(.c) void {
        _ = @atomicRmw(i64, &of(self).compute_live, .Sub, 1, .monotonic);
        destroyHandle(self, h);
    }

    fn createRenderPipeline(self: ?*abi_render.ke_gpu_device, _: [*c]const abi_render.ke_gpu_render_pipeline_params, out: [*c]abi_render.ke_gpu_pipeline) callconv(.c) abi_result.ke_result {
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    fn createSampler(self: ?*abi_render.ke_gpu_device, _: [*c]const abi_render.ke_gpu_sampler_params, out: [*c]abi_render.ke_gpu_sampler) callconv(.c) abi_result.ke_result {
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    /// Refused through `spendFallible`: once the budget is spent it fails as general and writes
    /// nothing.
    fn createShaderModule(self: ?*abi_render.ke_gpu_device, _: [*c]const abi_render.ke_gpu_shader_module_params, out: [*c]abi_render.ke_gpu_shader_module) callconv(.c) abi_result.ke_result {
        if (!spendFallible(self)) return abi_result.KE_RESULT_GENERAL;
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    fn shaderLanguage(_: ?*abi_render.ke_gpu_device) callconv(.c) abi_render.ke_gpu_shader_language {
        return abi_render.KE_GPU_SHADER_LANG_WGSL;
    }

    /// Calls the callback before returning, with a freshly minted handle, so the callback
    /// never runs later.
    fn createRenderPipelineAsync(self: ?*abi_render.ke_gpu_device, _: [*c]const abi_render.ke_gpu_render_pipeline_params, on_ready: ?*const fn (abi_render.ke_gpu_pipeline, ?*anyopaque) callconv(.c) void, user: ?*anyopaque) callconv(.c) void {
        if (on_ready) |ready| ready(mint(self), user);
    }

    fn createTexture(self: ?*abi_render.ke_gpu_device, p: [*c]const abi_render.ke_gpu_texture_params, out: [*c]abi_render.ke_gpu_texture) callconv(.c) abi_result.ke_result {
        of(self).texture_label = p.*.label;
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    fn createTextureView(self: ?*abi_render.ke_gpu_device, _: abi_render.ke_gpu_texture, p: [*c]const abi_render.ke_gpu_texture_view_params, out: [*c]abi_render.ke_gpu_texture_view) callconv(.c) abi_result.ke_result {
        of(self).texture_view_label = p.*.label;
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    fn writeBuffer(self: ?*abi_render.ke_gpu_device, _: abi_render.ke_gpu_buffer, _: u64, _: ?*const anyopaque, size: usize) callconv(.c) void {
        const d = of(self);
        d.buffer_writes += 1;
        d.bytes_written += size;
    }

    fn defaultQueue(_: ?*abi_render.ke_gpu_device) callconv(.c) abi_render.ke_gpu_queue {
        return 1;
    }

    fn queryExtension(_: ?*abi_render.ke_gpu_device, _: [*c]const u8) callconv(.c) ?*const anyopaque {
        return null;
    }

    fn ndcConvention(_: ?*abi_render.ke_gpu_device) callconv(.c) abi_render.ke_ndc_convention {
        return .{ .z_zero_to_one = true, .y_flip = true };
    }

    /// The handle is not checked: each call gives back one count, so releasing the same
    /// handle twice counts twice.
    fn destroyHandle(self: ?*abi_render.ke_gpu_device, _: u64) callconv(.c) void {
        _ = @atomicRmw(i64, &of(self).live, .Sub, 1, .monotonic);
    }
};

/// Fake render target. `acquired` is a flag set by `acquire`, not a count, and
/// `presented` is the only tally kept.
pub const Target = struct {
    vtable: abi_render.ke_gpu_render_target,
    acquired: bool,
    presented: u32,
    width: u32,
    height: u32,

    pub fn init(self: *Target) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_gpu_render_target), .acquired = false, .presented = 0, .width = 1, .height = 1 };
        self.vtable.handle = self;
        self.vtable.acquire = &acquire;
        self.vtable.present = &present;
        self.vtable.size = &size;
        self.vtable.format = &format;
    }

    pub fn api(self: *Target) *abi_render.ke_gpu_render_target {
        return &self.vtable;
    }

    fn of(self: ?*abi_render.ke_gpu_render_target) *Target {
        return @ptrCast(@alignCast(self.?.handle));
    }

    /// Repeated acquires are not counted: `acquired` is a flag.
    fn acquire(self: ?*abi_render.ke_gpu_render_target, out: [*c]abi_render.ke_gpu_texture_view) callconv(.c) abi_result.ke_result {
        of(self).acquired = true;
        out.* = 1;
        return abi_result.KE_OK;
    }

    /// Fails as an invalid argument and leaves `presented` alone unless an acquire came first.
    fn present(self: ?*abi_render.ke_gpu_render_target) callconv(.c) abi_result.ke_result {
        const t = of(self);
        if (!t.acquired) return abi_result.KE_RESULT_INVALID_ARGUMENT;
        t.acquired = false;
        t.presented += 1;
        return abi_result.KE_OK;
    }

    fn size(self: ?*abi_render.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
        if (out_w != null) out_w.* = of(self).width;
        if (out_h != null) out_h.* = of(self).height;
    }

    fn format(_: ?*abi_render.ke_gpu_render_target) callconv(.c) abi_render.ke_gpu_texture_format {
        return abi_render.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    }
};

/// Fake resource binder. `live` counts the layouts, sets and materials handed out and not
/// destroyed; every handle is read from and advanced in `next`.
pub const Binder = struct {
    vtable: abi_render.ke_render_resource_binder,
    next: u64,
    live: i64,

    pub fn init(self: *Binder) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_render_resource_binder), .next = 1, .live = 0 };
        self.vtable.handle = self;
        self.vtable.provide = &provide;
        self.vtable.create_shader_layout = &createShaderLayout;
        self.vtable.destroy_shader_layout = &destroyHandle;
        self.vtable.pipeline_layouts = &pipelineLayouts;
        self.vtable.create_set = &createSet;
        self.vtable.destroy_set = &destroyHandle;
        self.vtable.bind_render_set = &bindRenderSet;
        self.vtable.bind_compute_set = &bindComputeSet;
        self.vtable.create_material = &createMaterial;
        self.vtable.destroy_material = &destroyHandle;
        self.vtable.bind_material = &bindMaterial;
    }

    pub fn api(self: *Binder) *abi_render.ke_render_resource_binder {
        return &self.vtable;
    }

    fn of(self: [*c]abi_render.ke_render_resource_binder) *Binder {
        return @ptrCast(@alignCast(self.*.handle));
    }

    fn mint(self: [*c]abi_render.ke_render_resource_binder) u64 {
        const b = of(self);
        b.live += 1;
        const h = b.next;
        b.next += 1;
        return h;
    }

    fn destroyHandle(self: [*c]abi_render.ke_render_resource_binder, h: u64) callconv(.c) void {
        if (h != 0) of(self).live -= 1;
    }

    fn provide(_: [*c]abi_render.ke_render_resource_binder, _: [*c]const abi_render.ke_render_shader_binding) callconv(.c) abi_result.ke_result {
        return abi_result.KE_OK;
    }

    fn createShaderLayout(self: [*c]abi_render.ke_render_resource_binder, _: [*c]const abi_render.ke_render_shader_layout_params, out: [*c]abi_render.ke_render_shader_layout) callconv(.c) abi_result.ke_result {
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    /// Writes no layout.
    fn pipelineLayouts(_: [*c]abi_render.ke_render_resource_binder, _: abi_render.ke_render_shader_layout, _: [*c]abi_render.ke_gpu_bind_group_layout, _: u32, out_count: [*c]u32) callconv(.c) abi_result.ke_result {
        out_count.* = 0;
        return abi_result.KE_OK;
    }

    fn createSet(self: [*c]abi_render.ke_render_resource_binder, _: abi_render.ke_render_shader_layout, _: [*c]const u8, _: [*c]const u8, _: [*c]const abi_render.ke_render_shader_binding, _: u32, out: [*c]abi_render.ke_render_resource_set) callconv(.c) abi_result.ke_result {
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    fn bindRenderSet(_: [*c]abi_render.ke_render_resource_binder, _: [*c]abi_render.ke_gpu_render_pass, _: abi_render.ke_render_resource_set, _: [*c]const u32, _: u32) callconv(.c) void {}

    fn bindComputeSet(_: [*c]abi_render.ke_render_resource_binder, _: [*c]abi_render.ke_gpu_compute_pass, _: abi_render.ke_render_resource_set, _: [*c]const u32, _: u32) callconv(.c) void {}

    fn createMaterial(self: [*c]abi_render.ke_render_resource_binder, _: [*c]const abi_render.ke_render_material_data, out: [*c]abi_render.ke_render_material_binding) callconv(.c) abi_result.ke_result {
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    fn bindMaterial(_: [*c]abi_render.ke_render_resource_binder, _: [*c]abi_render.ke_gpu_render_pass, _: abi_render.ke_render_shader_layout, _: abi_render.ke_render_material_binding) callconv(.c) void {}
};

/// Fake render service. Every id it hands out is read from and advanced in `next`, one
/// sequence shared by all its methods. It answers `resource_binder` with `binder`.
pub const Core = struct {
    vtable: abi_render.ke_render_service,
    next: u64,
    shader_loads_fail: bool,
    device: *abi_render.ke_gpu_device,
    binder: Binder,
    links: i64,

    pub fn init(self: *Core, device: *abi_render.ke_gpu_device) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_render_service), .next = 1, .shader_loads_fail = false, .device = device, .binder = undefined, .links = 0 };
        self.binder.init();
        self.vtable.handle = self;
        self.vtable.resource_binder = &resourceBinder;
        self.vtable.material_binding = &materialBinding;
        self.vtable.load_shader = &loadShader;
        self.vtable.backbuffer_format = &backbufferFormat;
        self.vtable.resource_format = &resourceFormat;
        self.vtable.resource_generation = &resourceGeneration;
        self.vtable.get_or_create_pipeline = &getOrCreatePipeline;
        self.vtable.cid = &cid;
        self.vtable.declare = &declare;
        self.vtable.import_buffer = &importBuffer;
        self.vtable.import_tag = &importTag;
        self.vtable.resource_view = &resourceView;
        self.vtable.texture_view = &textureView;
        self.vtable.white_texture = &whiteTexture;
        self.vtable.resource_buffer = &resourceBuffer;
        self.vtable.resource_buffer_size = &resourceBufferSize;
        self.vtable.join_chain = &joinChain;
        self.vtable.leave_chain = &leaveChain;
        self.vtable.chain_format = &chainFormat;
    }

    /// Counts the links held in `links`.
    fn joinChain(self: ?*abi_render.ke_render_service, _: abi_render.ke_render_stage, _: abi_render.ke_render_chain_mode, out: [*c]abi_render.ke_render_chain_link) callconv(.c) abi_result.ke_result {
        const core: *Core = @ptrCast(@alignCast(self.?.handle));
        core.links += 1;
        out.* = @intCast(mint(self));
        return abi_result.KE_OK;
    }

    fn leaveChain(self: ?*abi_render.ke_render_service, _: abi_render.ke_render_chain_link) callconv(.c) void {
        const core: *Core = @ptrCast(@alignCast(self.?.handle));
        core.links -= 1;
    }

    fn chainFormat(_: ?*abi_render.ke_render_service, stage: abi_render.ke_render_stage) callconv(.c) abi_render.ke_gpu_texture_format {
        return if (stage >= abi_render.KE_RENDER_STAGE_TONEMAP) abi_render.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM else abi_render.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    }

    fn backbufferFormat(_: ?*abi_render.ke_render_service) callconv(.c) abi_render.ke_gpu_texture_format {
        return abi_render.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    }

    /// Knows no resource, so a pass declares every one it writes.
    fn resourceFormat(_: ?*abi_render.ke_render_service, _: [*c]const u8) callconv(.c) abi_render.ke_gpu_texture_format {
        return abi_render.KE_GPU_TEXTURE_FORMAT_INVALID;
    }

    fn resourceGeneration(_: [*c]abi_render.ke_render_service) callconv(.c) u32 {
        return 0;
    }

    pub fn api(self: *Core) *abi_render.ke_render_service {
        return &self.vtable;
    }

    /// Returns the current `next` and advances it without atomics, unlike the device's
    /// `mint`, so calls must not overlap.
    fn mint(self: ?*abi_render.ke_render_service) u64 {
        const core: *Core = @ptrCast(@alignCast(self.?.handle));
        const h = core.next;
        core.next += 1;
        return h;
    }

    /// Fails as general while `shader_loads_fail` is set, and writes nothing.
    fn loadShader(self: ?*abi_render.ke_render_service, _: [*c]const u8, _: abi_render.ke_gpu_shader_stage, out: [*c]abi_render.ke_gpu_shader_module) callconv(.c) abi_result.ke_result {
        const core: *Core = @ptrCast(@alignCast(self.?.handle));
        if (core.shader_loads_fail) return abi_result.KE_RESULT_GENERAL;
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    fn resourceBinder(self: [*c]abi_render.ke_render_service) callconv(.c) [*c]abi_render.ke_render_resource_binder {
        const core: *Core = @ptrCast(@alignCast(self.*.handle));
        return core.binder.api();
    }

    fn materialBinding(self: [*c]abi_render.ke_render_service, _: abi_render.ke_material_handle) callconv(.c) abi_render.ke_render_material_binding {
        return mint(self);
    }

    fn getOrCreatePipeline(self: ?*abi_render.ke_render_service, _: [*c]const abi_render.ke_gpu_render_pipeline_params) callconv(.c) abi_render.ke_gpu_pipeline {
        return mint(self);
    }

    /// Does not remember the name, so the same name gives a different id on each call.
    fn cid(self: ?*abi_render.ke_render_service, _: [*c]const u8) callconv(.c) abi_ecs.ke_component_id {
        return @intCast(mint(self));
    }

    fn declare(self: ?*abi_render.ke_render_service, _: [*c]const abi_render.ke_render_resource_params, out: [*c]abi_ecs.ke_component_id) callconv(.c) abi_result.ke_result {
        out.* = @intCast(mint(self));
        return abi_result.KE_OK;
    }

    fn importBuffer(self: ?*abi_render.ke_render_service, _: [*c]const u8, _: abi_render.ke_gpu_buffer, _: u64, out: [*c]abi_ecs.ke_component_id) callconv(.c) abi_result.ke_result {
        out.* = @intCast(mint(self));
        return abi_result.KE_OK;
    }

    fn importTag(self: ?*abi_render.ke_render_service, _: [*c]const u8, out: [*c]abi_ecs.ke_component_id) callconv(.c) abi_result.ke_result {
        out.* = @intCast(mint(self));
        return abi_result.KE_OK;
    }

    fn resourceView(self: ?*abi_render.ke_render_service, _: [*c]const u8) callconv(.c) abi_render.ke_gpu_texture_view {
        return mint(self);
    }

    fn textureView(self: ?*abi_render.ke_render_service, _: abi_render.ke_texture_handle) callconv(.c) abi_render.ke_gpu_texture_view {
        return mint(self);
    }

    fn whiteTexture(self: ?*abi_render.ke_render_service) callconv(.c) abi_render.ke_texture_handle {
        return .{ .bits = @intCast(mint(self)) };
    }

    fn resourceBuffer(self: ?*abi_render.ke_render_service, _: [*c]const u8) callconv(.c) abi_render.ke_gpu_buffer {
        return mint(self);
    }

    fn resourceBufferSize(_: ?*abi_render.ke_render_service, _: [*c]const u8) callconv(.c) u64 {
        return 256;
    }
};

/// Fake runtime. `live` holds the registered system ids in registration order, valid up to
/// `live_count`. `registered` only grows, so a system id is never handed out twice.
pub const Runtime = struct {
    vtable: abi_runtime.ke_runtime,
    registered: u32,
    limit: u32,
    live: [64]u64,
    live_count: u32,

    pub fn init(self: *Runtime) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_runtime.ke_runtime), .registered = 0, .limit = std.math.maxInt(u32), .live = undefined, .live_count = 0 };
        self.vtable.handle = self;
        self.vtable.register_system = &registerSystem;
        self.vtable.unregister_system = &unregisterSystem;
        self.vtable.last_system = &lastSystem;
        self.vtable.declare_self_ordered = &declareSelfOrdered;
    }

    fn declareSelfOrdered(_: ?*abi_runtime.ke_runtime, _: abi_ecs.ke_component_id) callconv(.c) abi_result.ke_result {
        return @intCast(abi_result.KE_OK);
    }

    pub fn api(self: *Runtime) *abi_runtime.ke_runtime {
        return &self.vtable;
    }

    /// Writes the null system id, fails with out of memory and changes nothing once
    /// `registered` has reached `limit`. Otherwise the new id is appended to `live`.
    fn registerSystem(self: ?*abi_runtime.ke_runtime, _: [*c]const abi_runtime.ke_runtime_system_params, out_id: [*c]abi_runtime.ke_system_id) callconv(.c) abi_result.ke_result {
        const rt: *Runtime = @ptrCast(@alignCast(self.?.handle));
        out_id.* = 0;
        if (rt.registered >= rt.limit) return @intCast(abi_result.KE_RESULT_OUT_OF_MEMORY);
        rt.registered += 1;
        rt.live[rt.live_count] = rt.registered;
        rt.live_count += 1;
        out_id.* = rt.registered;
        return @intCast(abi_result.KE_OK);
    }

    /// Fails with not found for an id that is not in `live`. Removing an id shifts the later
    /// ones down, keeping registration order. `registered` is not lowered, so ids stay unique.
    fn unregisterSystem(self: ?*abi_runtime.ke_runtime, id: abi_runtime.ke_system_id) callconv(.c) abi_result.ke_result {
        const rt: *Runtime = @ptrCast(@alignCast(self.?.handle));
        for (0..rt.live_count) |i| {
            if (rt.live[i] != id) continue;
            var j = i;
            while (j + 1 < rt.live_count) : (j += 1) rt.live[j] = rt.live[j + 1];
            rt.live_count -= 1;
            return @intCast(abi_result.KE_OK);
        }
        return @intCast(abi_result.KE_RESULT_NOT_FOUND);
    }

    fn lastSystem(self: ?*abi_runtime.ke_runtime) callconv(.c) abi_runtime.ke_system_id {
        const rt: *Runtime = @ptrCast(@alignCast(self.?.handle));
        return if (rt.live_count == 0) 0 else rt.live[rt.live_count - 1];
    }
};

/// Fake scene tree. Answers `generation` as its hierarchy generation, which a test moves by
/// hand.
pub const Tree = struct {
    vtable: abi_framework.ke_scene_tree,
    generation: u64,

    pub fn init(self: *Tree) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_framework.ke_scene_tree), .generation = 0 };
        self.vtable.handle = self;
        self.vtable.hierarchy_generation = &hierarchyGeneration;
    }

    pub fn api(self: *Tree) *abi_framework.ke_scene_tree {
        return &self.vtable;
    }

    fn hierarchyGeneration(self: ?*abi_framework.ke_scene_tree) callconv(.c) u64 {
        const t: *Tree = @ptrCast(@alignCast(self.?.handle));
        return t.generation;
    }
};

/// Fake ecs. Component and query ids are both drawn from `next`, so they never collide.
pub const Ecs = struct {
    vtable: abi_ecs.ke_ecs,
    next: u32,

    pub fn init(self: *Ecs) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_ecs.ke_ecs), .next = 1 };
        self.vtable.handle = self;
        self.vtable.component_register = &componentRegister;
        self.vtable.query_register = &queryRegister;
    }

    pub fn api(self: *Ecs) *abi_ecs.ke_ecs {
        return &self.vtable;
    }

    fn mint(self: ?*abi_ecs.ke_ecs) u32 {
        const e: *Ecs = @ptrCast(@alignCast(self.?.handle));
        const id = e.next;
        e.next += 1;
        return id;
    }

    fn componentRegister(self: ?*abi_ecs.ke_ecs, _: [*c]const abi_ecs.ke_component_params, out_cid: [*c]abi_ecs.ke_component_id) callconv(.c) abi_result.ke_result {
        out_cid.* = mint(self);
        return @intCast(abi_result.KE_OK);
    }

    fn queryRegister(self: ?*abi_ecs.ke_ecs, _: [*c]const abi_ecs.ke_component_id, _: usize, out_query: [*c]abi_ecs.ke_query_id) callconv(.c) abi_result.ke_result {
        out_query.* = mint(self);
        return @intCast(abi_result.KE_OK);
    }
};

/// Fake world. It stores nothing: every field table and apply function is accepted as
/// given.
pub const World = struct {
    vtable: abi_framework.ke_world,

    pub fn init(self: *World) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_framework.ke_world) };
        self.vtable.handle = self;
        self.vtable.register_component_fields = &registerFields;
        self.vtable.register_component_apply = &registerApply;
    }

    pub fn api(self: *World) *abi_framework.ke_world {
        return &self.vtable;
    }

    fn registerFields(_: ?*abi_framework.ke_world, _: abi_ecs.ke_component_id, _: [*c]const abi_ecs.ke_component_field, _: u32) callconv(.c) abi_result.ke_result {
        return abi_result.KE_OK;
    }

    fn registerApply(_: ?*abi_framework.ke_world, _: abi_ecs.ke_component_id, _: abi_framework.ke_component_apply_fn, _: ?*anyopaque) callconv(.c) abi_result.ke_result {
        return abi_result.KE_OK;
    }
};

//! Doubles of the contracts this plugin's tests run against, with only the slots they reach.

const std = @import("std");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");

/// Fake of the GPU device contract. `api` returns the vtable pointer and is valid only after
/// `init`. `live` counts the handles minted and not released. `fallible_created` against
/// `fallible_budget` is the only way a creation is refused. A refused creation fails as general,
/// writes no handle and leaves every counter as it was. Command recording keeps no history: one
/// record per kind of pass is handed back, and only the latest label and the depth of open debug
/// groups are kept.
pub const Device = struct {
    vtable: abi_render.ke_gpu_device,
    next: u64,
    live: i64,
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
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_gpu_device), .next = 1, .live = 0, .fallible_created = 0, .fallible_budget = std.math.maxInt(u32), .encoder = undefined, .render_pass = undefined, .compute_pass = undefined, .command_buffer = undefined, .texture_label = null, .texture_view_label = null, .render_pass_label = null, .render_passes = 0, .submitted = 0, .color_load = 0, .depth_load = null, .compute_pass_label = null, .debug_group_label = null, .debug_groups_open = 0, .buffer_writes = 0, .bytes_written = 0 };
        self.vtable.handle = self;
        self.vtable.create_buffer = &createBuffer;
        self.vtable.create_render_pipeline = &createRenderPipeline;
        self.vtable.create_sampler = &createSampler;
        self.vtable.destroy_buffer = &destroyHandle;
        self.vtable.destroy_pipeline = &destroyHandle;
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

/// Fake resource binder. `live` counts the layouts, sets and materials handed out and not
/// destroyed. Every handle is read from and advanced in `next`.
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
        self.vtable.create_material = &createMaterial;
        self.vtable.destroy_material = &destroyHandle;
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

    fn createMaterial(self: [*c]abi_render.ke_render_resource_binder, _: [*c]const abi_render.ke_render_material_data, out: [*c]abi_render.ke_render_material_binding) callconv(.c) abi_result.ke_result {
        out.* = mint(self);
        return abi_result.KE_OK;
    }
};

/// Fake ecs. Component ids are drawn from `next`.
pub const Ecs = struct {
    vtable: abi_ecs.ke_ecs,
    next: u32,

    pub fn init(self: *Ecs) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_ecs.ke_ecs), .next = 1 };
        self.vtable.handle = self;
        self.vtable.component_register = &componentRegister;
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
};

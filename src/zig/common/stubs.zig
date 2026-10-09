//! Fakes of the engine contracts that the render and framework code is written against, for unit
//! tests that must run with no GPU, window or ecs. `Stubs` takes the translated C namespace and
//! returns one struct per contract: `Device`, `Target`, `Core` (the render service), `Runtime`,
//! `Ecs` and `World`. Each struct embeds its vtable, points the handle of that vtable back at
//! itself and fills every slot with a function of the same struct, so an instance must stay where
//! `init` put it.
//!
//! The fakes count instead of doing. Handles and ids come from a counter of the struct that mints
//! them, and the device also tracks how many handles are live and how many of those are compute
//! pipelines, so a test can check that everything created was released. Refusal is set by the
//! test: the device refuses buffers, bind groups and shader modules once its budget of fallible
//! creations is spent, the render service refuses shader loads while told to, the runtime refuses
//! a registration at its limit, and a target refuses a present that no acquire preceded. A refusal
//! is an invalid handle, a null id or false, it never fills the error output and it leaves every
//! counter as it was.
//!
//! Command recording keeps no history. The device hands back one record per kind of pass and keeps
//! only the latest label and the depth of open debug groups; ending, submitting and polling do
//! nothing. The ecs mints ids and the world accepts every registration without storing it.

const std = @import("std");

/// Returns the fake structs for the contract types of `c`, the cimport it is given. Each struct
/// stores its own address as the vtable `handle`, so it must not move between `init` and its last
/// use.
pub fn Stubs(comptime c: type) type {
    return struct {
        /// Fake of the GPU device contract. `api` returns the vtable pointer and is valid only
        /// after `init`. `live` counts the handles minted and not released, `compute_live` counts
        /// the compute pipelines among them, and `fallible_created` against `fallible_budget` is
        /// the only way a creation is refused.
        pub const Device = struct {
            vtable: c.ke_gpu_device,
            next: u64,
            live: i64,
            compute_live: i64,
            fallible_created: u32,
            fallible_budget: u32,
            encoder: c.ke_gpu_command_encoder,
            render_pass: c.ke_gpu_render_pass,
            compute_pass: c.ke_gpu_compute_pass,
            command_buffer: c.ke_gpu_command_buffer,
            texture_label: [*c]const u8,
            texture_view_label: [*c]const u8,
            render_pass_label: [*c]const u8,
            compute_pass_label: [*c]const u8,
            debug_group_label: [*c]const u8,
            debug_groups_open: i32,

            pub fn init(self: *Device) void {
                self.* = .{ .vtable = std.mem.zeroes(c.ke_gpu_device), .next = 1, .live = 0, .compute_live = 0, .fallible_created = 0, .fallible_budget = std.math.maxInt(u32), .encoder = undefined, .render_pass = undefined, .compute_pass = undefined, .command_buffer = undefined, .texture_label = null, .texture_view_label = null, .render_pass_label = null, .compute_pass_label = null, .debug_group_label = null, .debug_groups_open = 0 };
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
                self.encoder = std.mem.zeroes(c.ke_gpu_command_encoder);
                self.encoder.handle = self;
                self.encoder.destroy = &destroyEncoder;
                self.encoder.begin_render_pass = &beginRenderPass;
                self.encoder.begin_compute_pass = &beginComputePass;
                self.encoder.finish = &finishEncoder;
                self.render_pass = std.mem.zeroes(c.ke_gpu_render_pass);
                self.render_pass.end = &endRenderPass;
                self.compute_pass = std.mem.zeroes(c.ke_gpu_compute_pass);
                self.compute_pass.handle = self;
                self.compute_pass.end = &endComputePass;
                self.compute_pass.push_debug_group = &pushDebugGroup;
                self.compute_pass.pop_debug_group = &popDebugGroup;
                self.command_buffer = std.mem.zeroes(c.ke_gpu_command_buffer);
                self.command_buffer.destroy = &destroyCommandBuffer;
            }

            fn encoderOwner(enc: ?*c.ke_gpu_command_encoder) *Device {
                return @ptrCast(@alignCast(enc.?.handle.?));
            }

            fn passOwner(pass: ?*c.ke_gpu_compute_pass) *Device {
                return @ptrCast(@alignCast(pass.?.handle.?));
            }

            /// Every begin returns the same render pass record, so the label of the latest begin
            /// replaces the one before it.
            fn beginRenderPass(enc: ?*c.ke_gpu_command_encoder, p: [*c]const c.ke_gpu_render_pass_params) callconv(.c) [*c]c.ke_gpu_render_pass {
                const self = encoderOwner(enc);
                self.render_pass_label = p.*.label;
                return &self.render_pass;
            }

            /// Every begin returns the same compute pass record, so the label of the latest begin
            /// replaces the one before it.
            fn beginComputePass(enc: ?*c.ke_gpu_command_encoder, p: [*c]const c.ke_gpu_compute_pass_params) callconv(.c) [*c]c.ke_gpu_compute_pass {
                const self = encoderOwner(enc);
                self.compute_pass_label = if (p != null) p.*.label else null;
                return &self.compute_pass;
            }

            fn endRenderPass(_: ?*c.ke_gpu_render_pass) callconv(.c) void {}

            fn endComputePass(_: ?*c.ke_gpu_compute_pass) callconv(.c) void {}

            fn pushDebugGroup(pass: ?*c.ke_gpu_compute_pass, label: [*c]const u8) callconv(.c) void {
                const self = passOwner(pass);
                self.debug_group_label = label;
                self.debug_groups_open += 1;
            }

            /// Nothing pairs it with a push, so the depth can drop below zero.
            fn popDebugGroup(pass: ?*c.ke_gpu_compute_pass) callconv(.c) void {
                passOwner(pass).debug_groups_open -= 1;
            }

            fn finishEncoder(enc: ?*c.ke_gpu_command_encoder) callconv(.c) [*c]c.ke_gpu_command_buffer {
                return &encoderOwner(enc).command_buffer;
            }

            fn destroyCommandBuffer(_: ?*c.ke_gpu_command_buffer) callconv(.c) void {}

            fn createCommandEncoder(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_command_encoder_params) callconv(.c) [*c]c.ke_gpu_command_encoder {
                return &of(self).encoder;
            }

            fn destroyEncoder(_: ?*c.ke_gpu_command_encoder) callconv(.c) void {}

            fn queueSubmit(_: ?*c.ke_gpu_device, _: c.ke_gpu_queue, _: [*c]const [*c]c.ke_gpu_command_buffer, _: u32) callconv(.c) void {}

            fn queuePoll(_: ?*c.ke_gpu_device, _: c.ke_gpu_queue) callconv(.c) void {}

            pub fn api(self: *Device) *c.ke_gpu_device {
                return &self.vtable;
            }

            fn of(self: ?*c.ke_gpu_device) *Device {
                return @ptrCast(@alignCast(self.?.handle));
            }

            /// Counts the handle in `live` and returns the value `next` held before this call. Both
            /// updates are atomic, so the device can mint from several threads at once.
            fn mint(self: ?*c.ke_gpu_device) u64 {
                const d = of(self);
                _ = @atomicRmw(i64, &d.live, .Add, 1, .monotonic);
                return @atomicRmw(u64, &d.next, .Add, 1, .monotonic);
            }

            /// Called by the creations that can be refused, before they mint. Plain operations,
            /// unlike `mint`, so it is not safe to call from several threads at once.
            fn spendFallible(self: ?*c.ke_gpu_device) bool {
                const d = of(self);
                if (d.fallible_created >= d.fallible_budget) return false;
                d.fallible_created += 1;
                return true;
            }

            /// Refused through `spendFallible`: once the budget is spent it returns the invalid
            /// handle and writes nothing to the error output.
            fn createBuffer(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_buffer_params, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_buffer {
                if (!spendFallible(self)) return c.KE_GPU_INVALID_HANDLE;
                return mint(self);
            }

            fn createBindGroupLayout(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_bind_group_layout_params) callconv(.c) c.ke_gpu_bind_group_layout {
                return mint(self);
            }

            /// Refused through `spendFallible`: once the budget is spent it returns the invalid
            /// handle and writes nothing to the error output.
            fn createBindGroup(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_bind_group_params, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_bind_group {
                if (!spendFallible(self)) return c.KE_GPU_INVALID_HANDLE;
                return mint(self);
            }

            /// Also counts toward `compute_live`, which `destroyComputePipeline` releases.
            fn createComputePipeline(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_compute_pipeline_params) callconv(.c) c.ke_gpu_pipeline {
                _ = @atomicRmw(i64, &of(self).compute_live, .Add, 1, .monotonic);
                return mint(self);
            }

            fn destroyComputePipeline(self: ?*c.ke_gpu_device, h: c.ke_gpu_pipeline) callconv(.c) void {
                _ = @atomicRmw(i64, &of(self).compute_live, .Sub, 1, .monotonic);
                destroyHandle(self, h);
            }

            fn createRenderPipeline(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_render_pipeline_params) callconv(.c) c.ke_gpu_pipeline {
                return mint(self);
            }

            fn createSampler(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_sampler_params) callconv(.c) c.ke_gpu_sampler {
                return mint(self);
            }

            /// Refused through `spendFallible`: once the budget is spent it returns the invalid
            /// handle and writes nothing to the error output.
            fn createShaderModule(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_shader_module_params, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_shader_module {
                if (!spendFallible(self)) return c.KE_GPU_INVALID_HANDLE;
                return mint(self);
            }

            fn shaderLanguage(_: ?*c.ke_gpu_device) callconv(.c) c.ke_gpu_shader_language {
                return c.KE_GPU_SHADER_LANG_WGSL;
            }

            /// Calls the callback before returning, with a freshly minted handle, so the callback
            /// never runs later.
            fn createRenderPipelineAsync(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_render_pipeline_params, on_ready: ?*const fn (c.ke_gpu_pipeline, ?*anyopaque) callconv(.c) void, user: ?*anyopaque) callconv(.c) void {
                if (on_ready) |ready| ready(mint(self), user);
            }

            fn createTexture(self: ?*c.ke_gpu_device, p: [*c]const c.ke_gpu_texture_params) callconv(.c) c.ke_gpu_texture {
                of(self).texture_label = p.*.label;
                return mint(self);
            }

            fn createTextureView(self: ?*c.ke_gpu_device, _: c.ke_gpu_texture, p: [*c]const c.ke_gpu_texture_view_params) callconv(.c) c.ke_gpu_texture_view {
                of(self).texture_view_label = p.*.label;
                return mint(self);
            }

            fn writeBuffer(_: ?*c.ke_gpu_device, _: c.ke_gpu_buffer, _: u64, _: ?*const anyopaque, _: usize) callconv(.c) void {}

            fn defaultQueue(_: ?*c.ke_gpu_device) callconv(.c) c.ke_gpu_queue {
                return 1;
            }

            fn queryExtension(_: ?*c.ke_gpu_device, _: [*c]const u8) callconv(.c) ?*const anyopaque {
                return null;
            }

            fn ndcConvention(_: ?*c.ke_gpu_device) callconv(.c) c.ke_ndc_convention {
                return .{ .z_zero_to_one = 1, .y_flip = 1, .clip_left_handed = 1 };
            }

            /// The handle is not checked: each call gives back one count, so releasing the same
            /// handle twice counts twice.
            fn destroyHandle(self: ?*c.ke_gpu_device, _: u64) callconv(.c) void {
                _ = @atomicRmw(i64, &of(self).live, .Sub, 1, .monotonic);
            }
        };

        /// Fake render target. `acquired` is a flag set by `acquire`, not a count, and
        /// `presented` is the only tally kept.
        pub const Target = struct {
            vtable: c.ke_gpu_render_target,
            acquired: bool,
            presented: u32,

            pub fn init(self: *Target) void {
                self.* = .{ .vtable = std.mem.zeroes(c.ke_gpu_render_target), .acquired = false, .presented = 0 };
                self.vtable.handle = self;
                self.vtable.acquire = &acquire;
                self.vtable.present = &present;
                self.vtable.size = &size;
                self.vtable.format = &format;
            }

            pub fn api(self: *Target) *c.ke_gpu_render_target {
                return &self.vtable;
            }

            fn of(self: ?*c.ke_gpu_render_target) *Target {
                return @ptrCast(@alignCast(self.?.handle));
            }

            /// Repeated acquires are not counted: `acquired` is a flag.
            fn acquire(self: ?*c.ke_gpu_render_target, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_texture_view {
                of(self).acquired = true;
                return 1;
            }

            /// Returns false and leaves `presented` alone unless an acquire came first.
            fn present(self: ?*c.ke_gpu_render_target, _: [*c][*c]c.ke_error) callconv(.c) bool {
                const t = of(self);
                if (!t.acquired) return false;
                t.acquired = false;
                t.presented += 1;
                return true;
            }

            fn size(_: ?*c.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
                if (out_w != null) out_w.* = 1;
                if (out_h != null) out_h.* = 1;
            }

            fn format(_: ?*c.ke_gpu_render_target) callconv(.c) c.ke_gpu_texture_format {
                return c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
            }
        };

        /// Fake render service. Every id it hands out is read from and advanced in `next`, one
        /// sequence shared by all its methods.
        pub const Core = struct {
            vtable: c.ke_render_service,
            next: u64,
            shader_loads_fail: bool,

            pub fn init(self: *Core) void {
                self.* = .{ .vtable = std.mem.zeroes(c.ke_render_service), .next = 1, .shader_loads_fail = false };
                self.vtable.handle = self;
                self.vtable.load_shader = &loadShader;
                self.vtable.backbuffer_format = &backbufferFormat;
                self.vtable.get_or_create_pipeline = &getOrCreatePipeline;
                self.vtable.cid = &cid;
                self.vtable.declare = &declare;
                self.vtable.import_buffer = &importBuffer;
                self.vtable.import_bind_group = &importBindGroup;
                self.vtable.import_tag = &importTag;
                self.vtable.resource_view = &resourceView;
                self.vtable.material_layout = &materialLayout;
                self.vtable.resource_bind_group_layout = &resourceBindGroupLayout;
                self.vtable.resource_bind_group = &resourceBindGroup;
                self.vtable.sampler = &sampler;
                self.vtable.texture_view = &textureView;
                self.vtable.white_texture = &whiteTexture;
                self.vtable.resource_buffer = &resourceBuffer;
                self.vtable.resource_buffer_size = &resourceBufferSize;
            }

            fn backbufferFormat(_: ?*c.ke_render_service) callconv(.c) c.ke_gpu_texture_format {
                return c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
            }

            pub fn api(self: *Core) *c.ke_render_service {
                return &self.vtable;
            }

            /// Returns the current `next` and advances it without atomics, unlike the device's
            /// `mint`, so calls must not overlap.
            fn mint(self: ?*c.ke_render_service) u64 {
                const core: *Core = @ptrCast(@alignCast(self.?.handle));
                const h = core.next;
                core.next += 1;
                return h;
            }

            /// Returns the invalid handle while `shader_loads_fail` is set, and writes nothing to
            /// the error output.
            fn loadShader(self: ?*c.ke_render_service, _: [*c]const u8, _: c.ke_gpu_shader_stage, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_shader_module {
                const core: *Core = @ptrCast(@alignCast(self.?.handle));
                if (core.shader_loads_fail) return c.KE_GPU_INVALID_HANDLE;
                return mint(self);
            }

            fn getOrCreatePipeline(self: ?*c.ke_render_service, _: [*c]const c.ke_gpu_render_pipeline_params) callconv(.c) c.ke_gpu_pipeline {
                return mint(self);
            }

            /// Does not remember the name, so the same name gives a different id on each call.
            fn cid(self: ?*c.ke_render_service, _: [*c]const u8) callconv(.c) c.ke_component_id {
                return @intCast(mint(self));
            }

            fn declare(self: ?*c.ke_render_service, _: [*c]const c.ke_render_resource_desc, _: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
                return @intCast(mint(self));
            }

            fn importBuffer(self: ?*c.ke_render_service, _: [*c]const u8, _: c.ke_gpu_buffer, _: u64, _: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
                return @intCast(mint(self));
            }

            fn importBindGroup(self: ?*c.ke_render_service, _: [*c]const u8, _: c.ke_gpu_bind_group, _: c.ke_gpu_bind_group_layout, _: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
                return @intCast(mint(self));
            }

            fn importTag(self: ?*c.ke_render_service, _: [*c]const u8, _: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
                return @intCast(mint(self));
            }

            fn resourceView(self: ?*c.ke_render_service, _: [*c]const u8) callconv(.c) c.ke_gpu_texture_view {
                return mint(self);
            }

            fn materialLayout(self: ?*c.ke_render_service) callconv(.c) c.ke_gpu_bind_group_layout {
                return mint(self);
            }

            fn resourceBindGroupLayout(self: ?*c.ke_render_service, _: [*c]const u8) callconv(.c) c.ke_gpu_bind_group_layout {
                return mint(self);
            }

            fn resourceBindGroup(self: ?*c.ke_render_service, _: [*c]const u8) callconv(.c) c.ke_gpu_bind_group {
                return mint(self);
            }

            fn sampler(self: ?*c.ke_render_service) callconv(.c) c.ke_gpu_sampler {
                return mint(self);
            }

            fn textureView(self: ?*c.ke_render_service, _: c.ke_texture_handle) callconv(.c) c.ke_gpu_texture_view {
                return mint(self);
            }

            fn whiteTexture(self: ?*c.ke_render_service) callconv(.c) c.ke_texture_handle {
                return .{ .bits = @intCast(mint(self)) };
            }

            fn resourceBuffer(self: ?*c.ke_render_service, _: [*c]const u8) callconv(.c) c.ke_gpu_buffer {
                return mint(self);
            }

            fn resourceBufferSize(_: ?*c.ke_render_service, _: [*c]const u8) callconv(.c) u64 {
                return 256;
            }
        };

        /// Fake runtime. `live` holds the registered system ids in registration order, valid up to
        /// `live_count`. `registered` only grows, so a system id is never handed out twice.
        pub const Runtime = struct {
            vtable: c.ke_runtime,
            registered: u32,
            limit: u32,
            live: [64]u64,
            live_count: u32,

            pub fn init(self: *Runtime) void {
                self.* = .{ .vtable = std.mem.zeroes(c.ke_runtime), .registered = 0, .limit = std.math.maxInt(u32), .live = undefined, .live_count = 0 };
                self.vtable.handle = self;
                self.vtable.register_system = &registerSystem;
                self.vtable.unregister_system = &unregisterSystem;
                self.vtable.last_system = &lastSystem;
            }

            pub fn api(self: *Runtime) *c.ke_runtime {
                return &self.vtable;
            }

            /// Returns the null system id and changes nothing once `registered` has reached
            /// `limit`. Otherwise the new id is appended to `live`.
            fn registerSystem(self: ?*c.ke_runtime, _: [*c]const c.ke_runtime_system_params, _: [*c][*c]c.ke_error) callconv(.c) c.ke_system_id {
                const rt: *Runtime = @ptrCast(@alignCast(self.?.handle));
                if (rt.registered >= rt.limit) return 0;
                rt.registered += 1;
                rt.live[rt.live_count] = rt.registered;
                rt.live_count += 1;
                return rt.registered;
            }

            /// Returns false for an id that is not in `live`. Removing an id shifts the later ones
            /// down, keeping registration order. `registered` is not lowered, so ids stay unique.
            fn unregisterSystem(self: ?*c.ke_runtime, id: c.ke_system_id, _: [*c][*c]c.ke_error) callconv(.c) bool {
                const rt: *Runtime = @ptrCast(@alignCast(self.?.handle));
                for (0..rt.live_count) |i| {
                    if (rt.live[i] != id) continue;
                    var j = i;
                    while (j + 1 < rt.live_count) : (j += 1) rt.live[j] = rt.live[j + 1];
                    rt.live_count -= 1;
                    return true;
                }
                return false;
            }

            fn lastSystem(self: ?*c.ke_runtime) callconv(.c) c.ke_system_id {
                const rt: *Runtime = @ptrCast(@alignCast(self.?.handle));
                return if (rt.live_count == 0) 0 else rt.live[rt.live_count - 1];
            }
        };

        /// Fake ecs. Component and query ids are both drawn from `next`, so they never collide.
        pub const Ecs = struct {
            vtable: c.ke_ecs,
            next: u32,

            pub fn init(self: *Ecs) void {
                self.* = .{ .vtable = std.mem.zeroes(c.ke_ecs), .next = 1 };
                self.vtable.handle = self;
                self.vtable.component_register = &componentRegister;
                self.vtable.query_register = &queryRegister;
            }

            pub fn api(self: *Ecs) *c.ke_ecs {
                return &self.vtable;
            }

            fn mint(self: ?*c.ke_ecs) u32 {
                const e: *Ecs = @ptrCast(@alignCast(self.?.handle));
                const id = e.next;
                e.next += 1;
                return id;
            }

            fn componentRegister(self: ?*c.ke_ecs, _: [*c]const u8, _: usize, _: [*c]const c.ke_component_field, _: u32, _: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
                return mint(self);
            }

            fn queryRegister(self: ?*c.ke_ecs, _: [*c]const c.ke_component_id, _: usize) callconv(.c) c.ke_query_id {
                return mint(self);
            }
        };

        /// Fake world. It stores nothing: every field table and apply function is accepted as
        /// given.
        pub const World = struct {
            vtable: c.ke_world,

            pub fn init(self: *World) void {
                self.* = .{ .vtable = std.mem.zeroes(c.ke_world) };
                self.vtable.handle = self;
                self.vtable.register_component_fields = &registerFields;
                self.vtable.register_component_apply = &registerApply;
            }

            pub fn api(self: *World) *c.ke_world {
                return &self.vtable;
            }

            fn registerFields(_: ?*c.ke_world, _: c.ke_component_id, _: [*c]const c.ke_component_field, _: u32, _: [*c][*c]c.ke_error) callconv(.c) bool {
                return true;
            }

            fn registerApply(_: ?*c.ke_world, _: c.ke_component_id, _: c.ke_component_apply_fn, _: ?*anyopaque, _: [*c][*c]c.ke_error) callconv(.c) bool {
                return true;
            }
        };
    };
}

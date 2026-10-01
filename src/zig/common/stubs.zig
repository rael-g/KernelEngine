const std = @import("std");

pub fn Stubs(comptime c: type) type {
    return struct {
        pub const Device = struct {
            vtable: c.ke_gpu_device,
            next: u64,
            live: i64,
            fallible_created: u32,
            fallible_budget: u32,

            pub fn init(self: *Device) void {
                self.* = .{ .vtable = std.mem.zeroes(c.ke_gpu_device), .next = 1, .live = 0, .fallible_created = 0, .fallible_budget = std.math.maxInt(u32) };
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
            }

            pub fn api(self: *Device) *c.ke_gpu_device {
                return &self.vtable;
            }

            fn of(self: ?*c.ke_gpu_device) *Device {
                return @ptrCast(@alignCast(self.?.handle));
            }

            fn mint(self: ?*c.ke_gpu_device) u64 {
                const d = of(self);
                const h = d.next;
                d.next += 1;
                d.live += 1;
                return h;
            }

            fn spendFallible(self: ?*c.ke_gpu_device) bool {
                const d = of(self);
                if (d.fallible_created >= d.fallible_budget) return false;
                d.fallible_created += 1;
                return true;
            }

            fn createBuffer(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_buffer_params, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_buffer {
                if (!spendFallible(self)) return c.KE_GPU_INVALID_HANDLE;
                return mint(self);
            }

            fn createBindGroupLayout(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_bind_group_layout_params) callconv(.c) c.ke_gpu_bind_group_layout {
                return mint(self);
            }

            fn createBindGroup(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_bind_group_params, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_bind_group {
                if (!spendFallible(self)) return c.KE_GPU_INVALID_HANDLE;
                return mint(self);
            }

            fn createComputePipeline(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_compute_pipeline_params) callconv(.c) c.ke_gpu_pipeline {
                return mint(self);
            }

            fn createRenderPipeline(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_render_pipeline_params) callconv(.c) c.ke_gpu_pipeline {
                return mint(self);
            }

            fn createSampler(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_sampler_params) callconv(.c) c.ke_gpu_sampler {
                return mint(self);
            }

            fn createShaderModule(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_shader_module_params, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_shader_module {
                if (!spendFallible(self)) return c.KE_GPU_INVALID_HANDLE;
                return mint(self);
            }

            fn shaderLanguage(_: ?*c.ke_gpu_device) callconv(.c) c.ke_gpu_shader_language {
                return c.KE_GPU_SHADER_LANG_WGSL;
            }

            fn createRenderPipelineAsync(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_render_pipeline_params, on_ready: ?*const fn (c.ke_gpu_pipeline, ?*anyopaque) callconv(.c) void, user: ?*anyopaque) callconv(.c) void {
                if (on_ready) |ready| ready(mint(self), user);
            }

            fn createTexture(self: ?*c.ke_gpu_device, _: [*c]const c.ke_gpu_texture_params) callconv(.c) c.ke_gpu_texture {
                return mint(self);
            }

            fn createTextureView(self: ?*c.ke_gpu_device, _: c.ke_gpu_texture, _: [*c]const c.ke_gpu_texture_view_params) callconv(.c) c.ke_gpu_texture_view {
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

            fn destroyHandle(self: ?*c.ke_gpu_device, _: u64) callconv(.c) void {
                of(self).live -= 1;
            }
        };

        pub const Core = struct {
            vtable: c.ke_render_service,
            next: u64,
            shader_loads_fail: bool,

            pub fn init(self: *Core) void {
                self.* = .{ .vtable = std.mem.zeroes(c.ke_render_service), .next = 1, .shader_loads_fail = false };
                self.vtable.handle = self;
                self.vtable.load_shader = &loadShader;
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

            pub fn api(self: *Core) *c.ke_render_service {
                return &self.vtable;
            }

            fn mint(self: ?*c.ke_render_service) u64 {
                const core: *Core = @ptrCast(@alignCast(self.?.handle));
                const h = core.next;
                core.next += 1;
                return h;
            }

            fn loadShader(self: ?*c.ke_render_service, _: [*c]const u8, _: c.ke_gpu_shader_stage, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_shader_module {
                const core: *Core = @ptrCast(@alignCast(self.?.handle));
                if (core.shader_loads_fail) return c.KE_GPU_INVALID_HANDLE;
                return mint(self);
            }

            fn getOrCreatePipeline(self: ?*c.ke_render_service, _: [*c]const c.ke_gpu_render_pipeline_params) callconv(.c) c.ke_gpu_pipeline {
                return mint(self);
            }

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

        pub const Runtime = struct {
            vtable: c.ke_runtime,
            registered: u32,
            limit: u32,

            pub fn init(self: *Runtime) void {
                self.* = .{ .vtable = std.mem.zeroes(c.ke_runtime), .registered = 0, .limit = std.math.maxInt(u32) };
                self.vtable.handle = self;
                self.vtable.register_system = &registerSystem;
            }

            pub fn api(self: *Runtime) *c.ke_runtime {
                return &self.vtable;
            }

            fn registerSystem(self: ?*c.ke_runtime, _: [*c]const c.ke_runtime_system_params, _: [*c][*c]c.ke_error) callconv(.c) c.ke_system_id {
                const rt: *Runtime = @ptrCast(@alignCast(self.?.handle));
                if (rt.registered >= rt.limit) return 0;
                rt.registered += 1;
                return rt.registered;
            }
        };

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

//! Doubles of the contracts this plugin's tests run against, with only the slots they reach.

const std = @import("std");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");

/// Fake resource binder. `live` counts the layouts, sets and materials handed out and not
/// destroyed. Every handle is read from and advanced in `next`.
pub const Binder = struct {
    vtable: abi_render.ke_render_resource_binder,
    next: u64,
    live: i64,

    pub fn init(self: *Binder) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_render_resource_binder), .next = 1, .live = 0 };
        self.vtable.handle = self;
        self.vtable.create_shader_layout = &createShaderLayout;
        self.vtable.destroy_shader_layout = &destroyHandle;
        self.vtable.pipeline_layouts = &pipelineLayouts;
        self.vtable.create_set = &createSet;
        self.vtable.destroy_set = &destroyHandle;
        self.vtable.bind_render_set = &bindRenderSet;
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
};

/// Fake of the GPU device contract. `api` returns the vtable pointer and is valid only after
/// `init`. `live` counts the handles minted and not released. `fallible_created` against
/// `fallible_budget` is the only way a creation is refused. A refused creation fails as general,
/// writes no handle and leaves every counter as it was.
pub const Device = struct {
    vtable: abi_render.ke_gpu_device,
    next: u64,
    live: i64,
    fallible_created: u32,
    fallible_budget: u32,
    render_pass: abi_render.ke_gpu_render_pass,
    compute_pass: abi_render.ke_gpu_compute_pass,

    pub fn init(self: *Device) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_gpu_device), .next = 1, .live = 0, .fallible_created = 0, .fallible_budget = std.math.maxInt(u32), .render_pass = undefined, .compute_pass = undefined };
        self.vtable.handle = self;
        self.vtable.create_buffer = &createBuffer;
        self.vtable.destroy_buffer = &destroyHandle;
        self.render_pass = std.mem.zeroes(abi_render.ke_gpu_render_pass);
        self.render_pass.end = &endRenderPass;
        self.render_pass.set_pipeline = &setRenderPipeline;
        self.render_pass.draw = &drawRenderPass;
        self.compute_pass = std.mem.zeroes(abi_render.ke_gpu_compute_pass);
        self.compute_pass.handle = self;
        self.compute_pass.end = &endComputePass;
    }

    fn endRenderPass(_: ?*abi_render.ke_gpu_render_pass) callconv(.c) void {}

    fn setRenderPipeline(_: ?*abi_render.ke_gpu_render_pass, _: abi_render.ke_gpu_pipeline) callconv(.c) void {}

    fn drawRenderPass(_: ?*abi_render.ke_gpu_render_pass, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}

    fn endComputePass(_: ?*abi_render.ke_gpu_compute_pass) callconv(.c) void {}

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

    /// The handle is not checked: each call gives back one count, so releasing the same
    /// handle twice counts twice.
    fn destroyHandle(self: ?*abi_render.ke_gpu_device, _: u64) callconv(.c) void {
        _ = @atomicRmw(i64, &of(self).live, .Sub, 1, .monotonic);
    }
};

/// Fake render service. Every id it hands out is read from and advanced in `next`, one sequence
/// shared by all its methods. It answers `resource_binder` with `binder`.
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
        self.vtable.load_shader = &loadShader;
        self.vtable.get_or_create_pipeline = &getOrCreatePipeline;
        self.vtable.cid = &cid;
        self.vtable.texture_view = &textureView;
        self.vtable.white_texture = &whiteTexture;
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

    fn getOrCreatePipeline(self: ?*abi_render.ke_render_service, _: [*c]const abi_render.ke_gpu_render_pipeline_params) callconv(.c) abi_render.ke_gpu_pipeline {
        return mint(self);
    }

    /// Does not remember the name, so the same name gives a different id on each call.
    fn cid(self: ?*abi_render.ke_render_service, _: [*c]const u8) callconv(.c) abi_ecs.ke_component_id {
        return @intCast(mint(self));
    }

    fn textureView(self: ?*abi_render.ke_render_service, _: abi_render.ke_texture_handle) callconv(.c) abi_render.ke_gpu_texture_view {
        return mint(self);
    }

    fn whiteTexture(self: ?*abi_render.ke_render_service) callconv(.c) abi_render.ke_texture_handle {
        return .{ .bits = @intCast(mint(self)) };
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

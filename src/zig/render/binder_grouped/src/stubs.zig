//! Doubles of the contracts this plugin's tests run against, with only the slots they reach.

const std = @import("std");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");

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

    pub fn init(self: *Device) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_gpu_device), .next = 1, .live = 0, .fallible_created = 0, .fallible_budget = std.math.maxInt(u32) };
        self.vtable.handle = self;
        self.vtable.create_buffer = &createBuffer;
        self.vtable.create_bind_group_layout = &createBindGroupLayout;
        self.vtable.create_bind_group = &createBindGroup;
        self.vtable.destroy_buffer = &destroyHandle;
        self.vtable.destroy_bind_group_layout = &destroyHandle;
        self.vtable.destroy_bind_group = &destroyHandle;
    }

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

    /// The handle is not checked: each call gives back one count, so releasing the same
    /// handle twice counts twice.
    fn destroyHandle(self: ?*abi_render.ke_gpu_device, _: u64) callconv(.c) void {
        _ = @atomicRmw(i64, &of(self).live, .Sub, 1, .monotonic);
    }
};

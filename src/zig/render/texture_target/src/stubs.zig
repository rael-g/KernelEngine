//! Doubles of the contracts this plugin's tests run against, with only the slots they reach.

const std = @import("std");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");

/// Fake of the GPU device contract. `api` returns the vtable pointer and is valid only after
/// `init`. `live` counts the handles minted and not released.
pub const Device = struct {
    vtable: abi_render.ke_gpu_device,
    next: u64,
    live: i64,
    texture_view_label: [*c]const u8,

    pub fn init(self: *Device) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_gpu_device), .next = 1, .live = 0, .texture_view_label = null };
        self.vtable.handle = self;
        self.vtable.create_texture_view = &createTextureView;
        self.vtable.destroy_texture_view = &destroyHandle;
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

    fn createTextureView(self: ?*abi_render.ke_gpu_device, _: abi_render.ke_gpu_texture, p: [*c]const abi_render.ke_gpu_texture_view_params, out: [*c]abi_render.ke_gpu_texture_view) callconv(.c) abi_result.ke_result {
        of(self).texture_view_label = p.*.label;
        out.* = mint(self);
        return abi_result.KE_OK;
    }

    /// The handle is not checked: each call gives back one count, so releasing the same
    /// handle twice counts twice.
    fn destroyHandle(self: ?*abi_render.ke_gpu_device, _: u64) callconv(.c) void {
        _ = @atomicRmw(i64, &of(self).live, .Sub, 1, .monotonic);
    }
};

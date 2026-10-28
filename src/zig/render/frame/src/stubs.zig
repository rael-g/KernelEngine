//! Doubles of the contracts this plugin's tests run against, with only the slots they reach.

const std = @import("std");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");

/// Fake of the GPU device contract. `api` returns the vtable pointer and is valid only after
/// `init`.
pub const Device = struct {
    vtable: abi_render.ke_gpu_device,

    pub fn init(self: *Device) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_gpu_device) };
        self.vtable.handle = self;
    }

    pub fn api(self: *Device) *abi_render.ke_gpu_device {
        return &self.vtable;
    }
};

/// Fake render service. Every id it hands out is read from and advanced in `next`, one sequence
/// shared by all its methods.
pub const Core = struct {
    vtable: abi_render.ke_render_service,
    next: u64,
    device: *abi_render.ke_gpu_device,

    pub fn init(self: *Core, device: *abi_render.ke_gpu_device) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render.ke_render_service), .next = 1, .device = device };
        self.vtable.handle = self;
        self.vtable.cid = &cid;
    }

    pub fn api(self: *Core) *abi_render.ke_render_service {
        return &self.vtable;
    }

    /// Returns the current `next` and advances it without atomics, so calls must not overlap.
    fn mint(self: ?*abi_render.ke_render_service) u64 {
        const core: *Core = @ptrCast(@alignCast(self.?.handle));
        const h = core.next;
        core.next += 1;
        return h;
    }

    /// Does not remember the name, so the same name gives a different id on each call.
    fn cid(self: ?*abi_render.ke_render_service, _: [*c]const u8) callconv(.c) abi_ecs.ke_component_id {
        return @intCast(mint(self));
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

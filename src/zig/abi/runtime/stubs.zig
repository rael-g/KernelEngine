//! A fake of the runtime contract, for unit tests that register systems with no scheduler.

const std = @import("std");
const abi_ecs = @import("ecs");
const abi_result = @import("result");
const abi_runtime = @import("abi");

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

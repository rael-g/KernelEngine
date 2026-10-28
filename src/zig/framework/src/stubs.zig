//! Doubles of the contracts this plugin's tests run against, with only the slots they reach.

const std = @import("std");
const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");

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

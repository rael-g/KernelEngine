//! A fake of the ecs contract, for unit tests that register components and queries with no world.

const std = @import("std");
const abi_ecs = @import("abi");
const abi_result = @import("result");

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

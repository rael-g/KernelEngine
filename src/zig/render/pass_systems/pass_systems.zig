//! The module of a render pass: the systems it registers in the render schedule's sets when it is
//! attached, and removes when it is detached.

const std = @import("std");
const abi_ecs = @import("abi_ecs");
const abi_module = @import("abi_module");
const abi_schedule = @import("abi_schedule");
const abi_result = @import("abi_result");

/// The render set a system joins.
pub const Set = enum { begin, prepare, queue, submit };

/// One system of a pass: what the schedule is given, the set it joins aside.
pub const System = struct {
    name: [*:0]const u8,
    execute: abi_schedule.c.ke_schedule_execute_fn,
    user: ?*anyopaque,
    set: Set,
    queries: []const abi_ecs.c.ke_ecs_query_desc = &.{},
    access: []const abi_ecs.c.ke_ecs_query_term = &.{},
};

/// The `ke_module` of a pass with `n` systems. It lives inside the pass's state, which is not moved
/// once `init` ran, since the module's handle points at it.
pub fn Systems(comptime n: usize) type {
    return struct {
        const Self = @This();

        module: abi_module.c.ke_module,
        systems: [n]System,
        schedule: ?*abi_schedule.c.ke_schedule = null,
        ids: [n]abi_schedule.c.ke_schedule_system_id = [_]abi_schedule.c.ke_schedule_system_id{0} ** n,
        sets: [n]abi_schedule.c.ke_schedule_set_id = [_]abi_schedule.c.ke_schedule_set_id{0} ** n,

        /// Makes the module of `systems`, which must outlive it.
        pub fn init(self: *Self, systems: [n]System) void {
            self.* = .{ .module = .{ .handle = self, .attach = attach, .detach = detach }, .systems = systems };
        }

        /// The handle a factory hands out: destroying it only detaches, the pass stays.
        pub fn handle(self: *Self) abi_module.c.ke_module_handle {
            return .{ .ref = &self.module, .destroy = detach };
        }

        fn of(self: ?*abi_module.c.ke_module) ?*Self {
            return @ptrCast(@alignCast((self orelse return null).handle));
        }

        fn setOf(targets: *const abi_module.c.ke_module_targets, set: Set) abi_schedule.c.ke_schedule_set_id {
            return switch (set) {
                .begin => targets.render_begin_set,
                .prepare => targets.render_prepare_set,
                .queue => targets.render_queue_set,
                .submit => targets.render_submit_set,
            };
        }

        /// Slot `attach`: registers every system in the render schedule, in order, taking back those
        /// registered before one the schedule refuses.
        fn attach(self: ?*abi_module.c.ke_module, targets_in: ?*const abi_module.c.ke_module_targets) callconv(.c) abi_result.c.ke_result {
            const s = of(self) orelse return abi_result.c.KE_RESULT_INVALID_ARGUMENT;
            const targets = targets_in orelse return abi_result.c.KE_RESULT_INVALID_ARGUMENT;
            if (s.schedule != null) return abi_result.c.KE_RESULT_NOT_SUPPORTED;
            const schedule: *abi_schedule.c.ke_schedule = @ptrCast(targets.render orelse return abi_result.c.KE_RESULT_INVALID_ARGUMENT);
            for (s.systems, 0..) |system, i| {
                s.sets[i] = setOf(targets, system.set);
                const desc: abi_schedule.c.ke_schedule_system_desc = .{
                    .name = system.name,
                    .user_data = system.user,
                    .execute = system.execute,
                    .queries = system.queries.ptr,
                    .query_count = @intCast(system.queries.len),
                    .access = system.access.ptr,
                    .access_count = @intCast(system.access.len),
                    .sets = s.sets[i..].ptr,
                    .set_count = 1,
                };
                const registered = schedule.register_system.?(schedule, &desc, &s.ids[i]);
                if (registered != abi_result.c.KE_OK) {
                    for (s.ids[0..i]) |id| _ = schedule.unregister_system.?(schedule, id);
                    return registered;
                }
            }
            s.schedule = schedule;
            return abi_result.c.KE_OK;
        }

        /// Slot `detach`: removes every system attach registered.
        pub fn detach(self: ?*abi_module.c.ke_module) callconv(.c) void {
            const s = of(self) orelse return;
            const schedule = s.schedule orelse return;
            for (s.ids) |id| _ = schedule.unregister_system.?(schedule, id);
            s.schedule = null;
        }
    };
}

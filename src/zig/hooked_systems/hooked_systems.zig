//! Systems registered each in the schedule and set of its hook when their owner is made, and removed when it is
//! destroyed.

const abi_ecs = @import("abi_ecs");
const abi_schedule = @import("abi_schedule");
const abi_result = @import("abi_result");

/// Where a system joins: a schedule and one of its sets, as a factory receives them.
pub const Hook = struct {
    schedule: ?*abi_schedule.c.ke_schedule,
    set: abi_schedule.c.ke_schedule_set_id,
};

/// One system: what the schedule is given, and the index of its hook among its owner's hooks.
pub const System = struct {
    name: [*:0]const u8,
    execute: abi_schedule.c.ke_schedule_execute_fn,
    user: ?*anyopaque,
    hook: usize,
    queries: []const abi_ecs.c.ke_ecs_query_desc = &.{},
    access: []const abi_ecs.c.ke_ecs_query_term = &.{},
};

/// The `n` registered systems of an owner. It lives inside the owner's state, which is not moved while they are
/// registered.
pub fn Systems(comptime n: usize) type {
    return struct {
        const Self = @This();

        schedules: [n]?*abi_schedule.c.ke_schedule = [_]?*abi_schedule.c.ke_schedule{null} ** n,
        ids: [n]abi_schedule.c.ke_schedule_system_id = [_]abi_schedule.c.ke_schedule_system_id{0} ** n,
        sets: [n]abi_schedule.c.ke_schedule_set_id = [_]abi_schedule.c.ke_schedule_set_id{0} ** n,

        /// Registers every system in the schedule and set of its hook, in order, taking back those registered
        /// before one the schedule refuses. A hook without a schedule is refused as an invalid argument before any
        /// system is registered.
        pub fn register(self: *Self, systems: [n]System, hooks: []const Hook) abi_result.c.ke_result {
            for (systems) |system| if (hooks[system.hook].schedule == null) return abi_result.c.KE_RESULT_INVALID_ARGUMENT;
            for (systems, 0..) |system, i| {
                const hook = hooks[system.hook];
                const schedule = hook.schedule.?;
                self.sets[i] = hook.set;
                const desc: abi_schedule.c.ke_schedule_system_desc = .{
                    .name = system.name,
                    .user_data = system.user,
                    .execute = system.execute,
                    .queries = system.queries.ptr,
                    .query_count = @intCast(system.queries.len),
                    .access = system.access.ptr,
                    .access_count = @intCast(system.access.len),
                    .sets = self.sets[i..].ptr,
                    .set_count = 1,
                };
                const registered = schedule.register_system.?(schedule, &desc, &self.ids[i]);
                if (registered != abi_result.c.KE_OK) {
                    self.unregister();
                    return registered;
                }
                self.schedules[i] = schedule;
            }
            return abi_result.c.KE_OK;
        }

        /// Removes every system `register` registered.
        pub fn unregister(self: *Self) void {
            for (&self.schedules, self.ids) |*schedule, id| {
                const s = schedule.* orelse continue;
                _ = s.unregister_system.?(s, id);
                schedule.* = null;
            }
        }
    };
}

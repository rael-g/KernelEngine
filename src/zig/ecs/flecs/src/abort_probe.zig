//! An executable that makes flecs fail an assertion through the installed hooks. It exits with a
//! failure status of its own if that assertion returns.

const std = @import("std");
const ecs_flecs = @import("ecs_flecs.zig");

pub fn main() void {
    ecs_flecs.debugTriggerRealFlecsAssertion();

    std.debug.print("PROBE: FAIL - returned normally, the hook did not fire\n", .{});
    std.process.exit(3);
}

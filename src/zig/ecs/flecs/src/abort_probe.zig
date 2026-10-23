//! An executable that runs the flecs abort hook the way flecs does on an internal failure, so its
//! log can be read by the test that starts it.

const ecs_flecs = @import("ecs_flecs.zig");

pub fn main() void {
    ecs_flecs.debugRunAbortHook("probe internal failure");
}

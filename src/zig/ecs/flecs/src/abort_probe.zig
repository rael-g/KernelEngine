// Standalone helper spawned by the "process ends cleanly" test — never run as
// part of `zig build test` itself.
//
// It calls ecs_flecs.debugTriggerRealFlecsAssertion(), which forces a genuine
// flecs internal assertion (asking for the mutable storage of a zero-size tag
// component; verified empirically against the vendored flecs build to raise
// "component cannot be a tag/zero sized" and call ecs_os_api.abort_). The
// correctness under test IS that the process ends — flecs's own assert macro
// assumes abort_ never returns and keeps running past the broken invariant if
// it does (confirmed while writing this probe: a stub that logs and returns
// lets flecs continue into a SECOND, unrelated crash a few calls later), so
// this cannot be exercised in-process the way flecsLogHandler's message
// formatting is.
//
// Imports ecs_flecs.zig as a module (rather than linking the compiled
// libke_ecs_flecs.so and calling only its public factory) specifically so it
// can reach debugTriggerRealFlecsAssertion: the plugin's public C surface has
// no path left to a flecs assert once the wrapper's own guards are in the
// way, by design.

const std = @import("std");
const ecs_flecs = @import("ecs_flecs.zig");

pub fn main() void {
    ecs_flecs.debugTriggerRealFlecsAssertion();

    std.debug.print("PROBE: FAIL - returned normally, the hook did not fire\n", .{});
    std.process.exit(3);
}

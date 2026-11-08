//! The audio module plugin: the system that plays the sounds the entities carry.

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_audio_module").logFn };

const std = @import("std");

comptime {
    _ = @import("sound.zig");
}

test "nothing the module allocated is left behind" {
    try @import("heap").expectNoLeaks();
}

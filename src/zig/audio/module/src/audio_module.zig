//! The audio module plugin: the system that plays the sounds the entities carry.

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_audio_module").logFn };

const std = @import("std");
const abi_part = @import("abi_part");
const part = @import("part");

comptime {
    _ = @import("sound.zig");
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(@import("sound.zig").ke_sound_create, .{ .name = "sound", .slots = &.{"ecs", "audio"}, .hooks = &.{"post_update"}, .set_log = @ptrCast(&@import("log").Destination("ke_audio_module").setLogCallback) }),
};

/// The library's parts.
export fn ke_audio_module_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

test "nothing the module allocated is left behind" {
    try @import("heap").expectNoLeaks();
}

test "the library's parts name sound and their slots" {
    var count: usize = 0;
    const all = ke_audio_module_parts(&count).?;
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualStrings("sound", std.mem.span(@as([*]const abi_part.c.ke_part, @ptrCast(all))[0].name.?));
    try std.testing.expectEqual(@as(usize, 3), @as([*]const abi_part.c.ke_part, @ptrCast(all))[0].slot_count);
}

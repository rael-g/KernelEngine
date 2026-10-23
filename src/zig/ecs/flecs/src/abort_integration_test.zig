//! Runs the abort probe as a child process and checks that the hook logs flecs's message and the
//! stack where flecs called it.

const std = @import("std");
const testing = std.testing;

const build_options = @import("build_options");

test "the abort hook logs flecs's message and the stack it was called from" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const result = try std.process.run(testing.allocator, io, .{
        .argv = &.{build_options.probe_exe_path},
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.indexOf(u8, result.stderr, "flecs internal failure:") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "probe internal failure") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "debugRunAbortHook") != null);
}


const std = @import("std");
const testing = std.testing;

const build_options = @import("build_options");

test "a real flecs internal assertion ends the process via E.fatal" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const result = try std.process.run(testing.allocator, io, .{
        .argv = &.{build_options.probe_exe_path},
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(result.term == .exited);
    try testing.expect(result.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "FATAL: [ke.ecs.flecs.fatal]") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "component cannot be a tag") != null);
}

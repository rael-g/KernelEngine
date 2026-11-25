//! The `ke_runner` contract over a window: a run handles the window's events and ticks the scheduler by the time
//! measured since the previous frame, until the window is closed or the program is asked to end.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_runner_window").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const abi_part = @import("abi_part");
const abi_result = @import("abi_result");
const abi_runner = @import("abi_runner");
const abi_scheduler = @import("abi_scheduler");
const abi_window = @import("abi_window");
const heap = @import("heap");
const part = @import("part");

const R = @import("result").Result(.{});
const log = std.log.scoped(.runner_window);
const gpa = heap.gpa;

const c = abi_runner.c;

/// The state behind the handle: what it ticks and pumps, and the `std.Io` it reads the clock through.
const State = struct {
    api: c.ke_runner,
    scheduler: *abi_scheduler.c.ke_scheduler,
    window: *abi_window.c.ke_window,
    threaded: std.Io.Threaded = .init_single_threaded,
};

fn stateOf(self: ?*c.ke_runner) ?*State {
    return @alignCast(@fieldParentPtr("api", self orelse return null));
}

fn failed(comptime slot: []const u8, err: R.Error) abi_result.c.ke_result {
    log.warn(slot ++ " failed: {t}", .{err});
    return R.code(err);
}

/// Slot `run`: frame by frame, handles the window's events, then ticks by the seconds since the previous frame,
/// the first frame by none; ends once the window is closed or the program is asked to end.
fn run(self: ?*c.ke_runner) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("run", error.InvalidArgument);
    const sched = s.scheduler;
    const window = s.window;
    const io = s.threaded.io();
    var previous = std.Io.Clock.awake.now(io);
    while (!window.should_close.?(window) and !sched.exit_requested.?(sched)) {
        window.poll_events.?(window);
        const current = std.Io.Clock.awake.now(io);
        const dt: f32 = @floatCast(@as(f64, @floatFromInt(previous.durationTo(current).nanoseconds)) / std.time.ns_per_s);
        previous = current;
        const ticked = sched.tick.?(sched, dt);
        if (ticked != R.ok) return ticked;
    }
    return R.ok;
}

/// Slot `destroy` of the handle.
fn destroy(self: ?*c.ke_runner) callconv(.c) void {
    const s = stateOf(self) orelse return;
    gpa.destroy(s);
}

/// The factory: a runner over a scheduler and a window it borrows.
export fn ke_runner_window_create(scheduler: ?*abi_scheduler.c.ke_scheduler, window: ?*abi_window.c.ke_window, out_runner: ?*c.ke_runner_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_runner orelse return failed("ke_runner_window_create", error.InvalidArgument);
    out.* = .{};
    const sched = scheduler orelse return failed("ke_runner_window_create", error.InvalidArgument);
    const win = window orelse return failed("ke_runner_window_create", error.InvalidArgument);
    const s = gpa.create(State) catch |err| return failed("ke_runner_window_create", err);
    s.* = .{ .api = .{ .run = &run }, .scheduler = sched, .window = win };
    s.api.handle = s;
    out.* = .{ .ref = &s.api, .destroy = &destroy };
    return R.ok;
}

const parts = [_]abi_part.c.ke_part{
    part.of(ke_runner_window_create, .{ .name = "runner_window", .slots = &.{ "scheduler", "window" }, .set_log = @ptrCast(&@import("log").Destination("ke_runner_window").setLogCallback) }),
};

/// The library's parts.
export fn ke_runner_window_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

const testing = std.testing;
const zsub = @import("zsub");

const Rig = struct {
    scheduler: zsub.For(abi_scheduler.c.ke_scheduler),
    window: zsub.For(abi_window.c.ke_window),
    runner: c.ke_runner_handle = .{},

    fn init(self: *Rig) !void {
        try self.scheduler.init();
        try self.window.init();
        _ = self.scheduler.when(.exit_requested).returns(false);
        try R.check(ke_runner_window_create(self.scheduler.api(), self.window.api(), &self.runner));
    }

    fn deinit(self: *Rig) void {
        self.runner.destroy.?(self.runner.ref);
        self.window.deinit();
        self.scheduler.deinit();
    }
};

test "a run handles the window's events and ticks once a frame until the window is closed" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.window.when(.should_close).returnsSeq(&.{ false, false, false, true });
    try R.check(rig.runner.ref.?.run.?(rig.runner.ref));
    try rig.window.received(.poll_events).times(3);
    try rig.scheduler.received(.tick).times(3);
}

test "a run ends once the program is asked to end" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.window.when(.should_close).returns(false);
    _ = rig.scheduler.when(.exit_requested).returnsSeq(&.{ false, true });
    try R.check(rig.runner.ref.?.run.?(rig.runner.ref));
    try rig.scheduler.received(.tick).times(1);
}

test "a tick that fails ends the run with its code" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.window.when(.should_close).returns(false);
    _ = rig.scheduler.when(.tick).returns(abi_result.c.KE_RESULT_GENERAL);
    try testing.expectEqual(abi_result.c.KE_RESULT_GENERAL, rig.runner.ref.?.run.?(rig.runner.ref));
    try rig.scheduler.received(.tick).times(1);
}

test "a runner without a scheduler or a window is refused" {
    var window: zsub.For(abi_window.c.ke_window) = undefined;
    try window.init();
    defer window.deinit();
    var h: c.ke_runner_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_runner_window_create(null, window.api(), &h)));
    try testing.expect(h.ref == null);
}

test "creating and destroying runners leaves no block allocated" {
    try heap.expectNoLeaks();
}

//! The `ke_scheduler` plugin: the frame loop, running the schedules it was given tick by tick, each
//! when its cadence says, the fixed ones at their own rate.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_scheduler").logFn };

const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const abi_scheduler = @import("abi_scheduler");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.scheduler);

const c = abi_scheduler.c;
const gpa = heap.gpa;

const Entry = struct {
    schedule: *abi_schedule.c.ke_schedule,
    cadence: c.ke_scheduler_cadence,
};

/// The state behind the `ke_scheduler` handle, whose `api.handle` points back at it. `entries` are
/// the schedules in the order they were added; `accumulated` is the time fixed steps have not yet
/// consumed. Only `exit` is touched by several threads.
const State = struct {
    api: c.ke_scheduler,
    entries: std.ArrayList(Entry) = .empty,
    fixed_dt: f32,
    fixed_dt_max_accum: f32,
    accumulated: f32 = 0,
    started: bool = false,
    shut_down: bool = false,
    exit: std.atomic.Value(bool) = .init(false),
};

fn stateOf(self: ?*c.ke_scheduler) ?*State {
    return @alignCast(@fieldParentPtr("api", self orelse return null));
}

fn reject(err: R.Error, comptime why: []const u8) R.Error {
    log.warn(why, .{});
    return err;
}

fn failed(comptime slot: []const u8, err: R.Error) abi_result.c.ke_result {
    log.warn(slot ++ " failed: {t}", .{err});
    return R.code(err);
}

/// Slot `add_schedule`.
fn addSchedule(self: ?*c.ke_scheduler, schedule: ?*abi_schedule.c.ke_schedule, cadence: c.ke_scheduler_cadence) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("add_schedule", error.InvalidArgument);
    append(s, schedule orelse return failed("add_schedule", error.InvalidArgument), cadence) catch |err| return failed("add_schedule", err);
    return R.ok;
}

fn append(s: *State, schedule: *abi_schedule.c.ke_schedule, cadence: c.ke_scheduler_cadence) R.Error!void {
    if (s.shut_down) return reject(error.NotSupported, "the scheduler was shut down");
    switch (cadence) {
        c.KE_SCHEDULER_CADENCE_EVERY_TICK, c.KE_SCHEDULER_CADENCE_FIXED, c.KE_SCHEDULER_CADENCE_STARTUP, c.KE_SCHEDULER_CADENCE_SHUTDOWN => {},
        else => return reject(error.InvalidArgument, "unknown cadence"),
    }
    try s.entries.append(gpa, .{ .schedule = schedule, .cadence = cadence });
}

fn runEntry(entry: Entry, dt: f32) R.Error!void {
    R.check(entry.schedule.run.?(entry.schedule, dt)) catch |err| {
        log.warn("a schedule failed: {t}", .{err});
        return err;
    };
}

fn runCadence(s: *State, cadence: c.ke_scheduler_cadence) R.Error!void {
    for (s.entries.items) |entry| {
        if (entry.cadence == cadence) try runEntry(entry, 0);
    }
}

/// Slot `tick`.
fn tick(self: ?*c.ke_scheduler, dt: f32) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("tick", error.InvalidArgument);
    tickSchedules(s, dt) catch |err| return failed("tick", err);
    return R.ok;
}

fn tickSchedules(s: *State, dt: f32) R.Error!void {
    if (s.shut_down) return reject(error.NotSupported, "the scheduler was shut down");
    if (!(dt >= 0)) return reject(error.InvalidArgument, "a tick needs a dt of zero or more");
    if (!s.started) {
        s.started = true;
        try runCadence(s, c.KE_SCHEDULER_CADENCE_STARTUP);
    }
    s.accumulated = @min(s.accumulated + dt, s.fixed_dt_max_accum);
    var steps: u32 = 0;
    while (s.accumulated >= s.fixed_dt) : (steps += 1) s.accumulated -= s.fixed_dt;
    const entries = s.entries.items;
    var i: usize = 0;
    while (i < entries.len) {
        switch (entries[i].cadence) {
            c.KE_SCHEDULER_CADENCE_EVERY_TICK => {
                try runEntry(entries[i], dt);
                i += 1;
            },
            c.KE_SCHEDULER_CADENCE_FIXED => {
                var end = i;
                while (end < entries.len and entries[end].cadence == c.KE_SCHEDULER_CADENCE_FIXED) end += 1;
                for (0..steps) |_| {
                    for (entries[i..end]) |entry| try runEntry(entry, s.fixed_dt);
                }
                i = end;
            },
            else => i += 1,
        }
    }
}

/// Slot `shutdown`.
fn shutdown(self: ?*c.ke_scheduler) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("shutdown", error.InvalidArgument);
    shutdownSchedules(s) catch |err| return failed("shutdown", err);
    return R.ok;
}

fn shutdownSchedules(s: *State) R.Error!void {
    if (s.shut_down) return;
    s.shut_down = true;
    if (!s.started) return;
    try runCadence(s, c.KE_SCHEDULER_CADENCE_SHUTDOWN);
}

/// Slot `request_exit`.
fn requestExit(self: ?*c.ke_scheduler) callconv(.c) void {
    const s = stateOf(self) orelse return;
    s.exit.store(true, .release);
}

/// Slot `exit_requested`.
fn exitRequested(self: ?*c.ke_scheduler) callconv(.c) bool {
    const s = stateOf(self) orelse return false;
    return s.exit.load(.acquire);
}

/// Slot `destroy` of the handle: shuts down for a caller that did not, then frees the state.
fn destroy(self: ?*c.ke_scheduler) callconv(.c) void {
    const s = stateOf(self) orelse return;
    shutdownSchedules(s) catch {};
    s.entries.deinit(gpa);
    gpa.destroy(s);
}

/// The factory: a scheduler with no schedule.
export fn ke_scheduler_create(config: ?*const c.ke_scheduler_config, out_scheduler: ?*c.ke_scheduler_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_scheduler orelse return failed("ke_scheduler_create", error.InvalidArgument);
    out.* = .{};
    const cfg = config orelse return failed("ke_scheduler_create", reject(error.InvalidArgument, "a scheduler needs its config"));
    if (!(cfg.fixed_dt > 0) or !(cfg.fixed_dt_max_accum > 0)) return failed("ke_scheduler_create", reject(error.InvalidArgument, "a scheduler needs a fixed_dt and a fixed_dt_max_accum greater than zero"));
    const s = gpa.create(State) catch |err| return failed("ke_scheduler_create", err);
    s.* = .{
        .api = .{
            .add_schedule = &addSchedule,
            .tick = &tick,
            .shutdown = &shutdown,
            .request_exit = &requestExit,
            .exit_requested = &exitRequested,
        },
        .fixed_dt = cfg.fixed_dt,
        .fixed_dt_max_accum = cfg.fixed_dt_max_accum,
    };
    s.api.handle = s;
    out.* = .{ .ref = &s.api, .destroy = &destroy };
    return R.ok;
}

const testing = std.testing;

const test_config: c.ke_scheduler_config = .{ .fixed_dt = 0.25, .fixed_dt_max_accum = 1.0 };

const Log = struct {
    letters: [32]u8 = undefined,
    dts: [32]f32 = undefined,
    count: usize = 0,

    fn text(l: *const Log) []const u8 {
        return l.letters[0..l.count];
    }
};

/// A schedule that writes its letter and dt into a shared log, or fails when told to.
const Fake = struct {
    api: abi_schedule.c.ke_schedule,
    log: *Log,
    letter: u8,
    fails: bool = false,

    fn init(f: *Fake, log_to: *Log, letter: u8) void {
        f.* = .{ .api = std.mem.zeroes(abi_schedule.c.ke_schedule), .log = log_to, .letter = letter };
        f.api.handle = f;
        f.api.run = &fakeRun;
    }
};

fn fakeRun(self: ?*abi_schedule.c.ke_schedule, dt: f32) callconv(.c) abi_result.c.ke_result {
    const f: *Fake = @ptrCast(@alignCast(self.?.handle.?));
    if (f.fails) return R.code(error.Io);
    f.log.letters[f.log.count] = f.letter;
    f.log.dts[f.log.count] = dt;
    f.log.count += 1;
    return R.ok;
}

const Rig = struct {
    handle: c.ke_scheduler_handle,
    sched: *c.ke_scheduler,
    log: Log = .{},
    fakes: [6]Fake = undefined,

    fn init(r: *Rig, cadences: []const c.ke_scheduler_cadence) !void {
        r.log = .{};
        try R.check(ke_scheduler_create(&test_config, &r.handle));
        r.sched = r.handle.ref.?;
        for (cadences, 0..) |cadence, i| {
            r.fakes[i].init(&r.log, @intCast('a' + i));
            try R.check(r.sched.add_schedule.?(r.sched, @ptrCast(&r.fakes[i].api), cadence));
        }
    }

    fn deinit(r: *Rig) void {
        r.handle.destroy.?(r.sched);
    }

    fn tick(r: *Rig, dt: f32) !void {
        try R.check(r.sched.tick.?(r.sched, dt));
    }
};

const every = c.KE_SCHEDULER_CADENCE_EVERY_TICK;
const fixed = c.KE_SCHEDULER_CADENCE_FIXED;
const startup = c.KE_SCHEDULER_CADENCE_STARTUP;
const shut = c.KE_SCHEDULER_CADENCE_SHUTDOWN;

test "the startup schedules run once, before every other schedule of the first tick, with a dt of zero" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, startup });
    defer rig.deinit();
    try rig.tick(0.1);
    try rig.tick(0.1);
    try testing.expectEqualStrings("baa", rig.log.text());
    try testing.expectEqual(0, rig.log.dts[0]);
    try testing.expectEqual(0.1, rig.log.dts[1]);
}

test "consecutive fixed schedules run together, in order, once per fixed step, with the fixed dt" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, fixed, fixed, every });
    defer rig.deinit();
    try rig.tick(0.5);
    try testing.expectEqualStrings("abcbcd", rig.log.text());
    try testing.expectEqual(0.25, rig.log.dts[1]);
}

test "the fixed schedules accumulate at their own rate, and a tick shorter than the step takes none" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{fixed});
    defer rig.deinit();
    try rig.tick(0.1);
    try testing.expectEqualStrings("", rig.log.text());
    try rig.tick(0.2);
    try testing.expectEqualStrings("a", rig.log.text());
}

test "a huge tick is capped so the fixed schedules cannot spiral" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{fixed});
    defer rig.deinit();
    try rig.tick(100);
    try testing.expectEqual(4, rig.log.count);
}

test "the shutdown schedules run once when the scheduler shuts down after a tick, and a tick after it is refused" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, shut });
    defer rig.deinit();
    try rig.tick(0);
    try R.check(rig.sched.shutdown.?(rig.sched));
    try R.check(rig.sched.shutdown.?(rig.sched));
    try testing.expectEqualStrings("ab", rig.log.text());
    try testing.expectEqual(R.code(error.NotSupported), rig.sched.tick.?(rig.sched, 0));
}

test "destroying a scheduler that ticked runs its shutdown schedules, and one that never ticked runs none" {
    var ticked: Rig = .{ .handle = undefined, .sched = undefined };
    try ticked.init(&.{shut});
    try ticked.tick(0);
    ticked.deinit();
    try testing.expectEqualStrings("a", ticked.log.text());
    var idle: Rig = .{ .handle = undefined, .sched = undefined };
    try idle.init(&.{shut});
    idle.deinit();
    try testing.expectEqualStrings("", idle.log.text());
}

test "a schedule that fails the tick keeps the later schedules from running" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, every });
    defer rig.deinit();
    rig.fakes[0].fails = true;
    try testing.expectEqual(R.code(error.Io), rig.sched.tick.?(rig.sched, 0));
    try testing.expectEqualStrings("", rig.log.text());
}

test "an unknown cadence, a null schedule and a negative dt are refused" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{});
    defer rig.deinit();
    var fake: Fake = undefined;
    fake.init(&rig.log, 'x');
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.add_schedule.?(rig.sched, @ptrCast(&fake.api), 9));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.add_schedule.?(rig.sched, null, every));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.tick.?(rig.sched, -1));
}

test "a request to exit is recorded and read back, and a fresh scheduler has none" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{});
    defer rig.deinit();
    try testing.expect(!rig.sched.exit_requested.?(rig.sched));
    rig.sched.request_exit.?(rig.sched);
    try testing.expect(rig.sched.exit_requested.?(rig.sched));
}

test "a fixed dt or a catch-up budget that is not greater than zero, or no config, is refused and leaves the handle zeroed" {
    var handle: c.ke_scheduler_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(&.{ .fixed_dt = 0, .fixed_dt_max_accum = 1 }, &handle));
    try testing.expectEqual(null, handle.ref);
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(&.{ .fixed_dt = 1, .fixed_dt_max_accum = 0 }, &handle));
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(null, &handle));
}

test "a slot given no scheduler refuses" {
    try testing.expectEqual(R.code(error.InvalidArgument), tick(null, 0));
    try testing.expectEqual(R.code(error.InvalidArgument), shutdown(null));
    try testing.expect(!exitRequested(null));
}

test "nothing the scheduler allocated is left behind" {
    try heap.expectNoLeaks();
}

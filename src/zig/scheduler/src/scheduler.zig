//! The `ke_scheduler` plugin: the frame loop, draining the job and async systems and running the
//! executables it was given tick by tick, each when its cadence says, the fixed ones at their own rate.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_scheduler").logFn };

const abi_result = @import("abi_result");
const abi_async = @import("abi_async");
const abi_completion = @import("abi_completion");
const abi_job = @import("abi_job");
const abi_scheduler = @import("abi_scheduler");
const heap = @import("heap");

const abi_settings = @import("abi_settings");
const abi_part = @import("abi_part");
const settings_schema = @import("settings_schema");
const R = @import("result").Result(.{});
const log = std.log.scoped(.scheduler);

const c = abi_scheduler.c;
const gpa = heap.gpa;

/// One added executable. `completed` is the number of its last run that completed, zero before one.
const Entry = struct {
    run: *const fn (?*anyopaque, f32, ?*?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result,
    user: ?*anyopaque,
    cadence: c.ke_scheduler_cadence,
    completed: std.atomic.Value(u64) = .init(0),
};

/// The state behind the `ke_scheduler` handle, whose `api.handle` points back at it. `entries` are
/// the executables in the order they were added; `accumulated` is the time fixed steps have not yet
/// consumed. `sequence` numbers the runs as they start. Bodies read `exit`, `sequence`, `alpha` and
/// each entry's `completed` while the thread calling tick writes them.
const State = struct {
    api: c.ke_scheduler,
    jobs: *abi_job.c.ke_job_system,
    async_system: *abi_async.c.ke_async,
    alpha: std.atomic.Value(f32) = .init(0),
    entries: std.ArrayList(Entry) = .empty,
    fixed_dt: f32,
    fixed_dt_max_accum: f32,
    accumulated: f32 = 0,
    started: bool = false,
    shut_down: bool = false,
    exit: std.atomic.Value(bool) = .init(false),
    sequence: std.atomic.Value(u64) = .init(0),
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

/// Slot `add`.
fn add(self: ?*c.ke_scheduler, run: c.ke_scheduler_run_fn, user: ?*anyopaque, cadence: c.ke_scheduler_cadence) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("add", error.InvalidArgument);
    append(s, run orelse return failed("add", error.InvalidArgument), user, cadence) catch |err| return failed("add", err);
    return R.ok;
}

fn append(s: *State, run: *const fn (?*anyopaque, f32, ?*?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result, user: ?*anyopaque, cadence: c.ke_scheduler_cadence) R.Error!void {
    if (s.shut_down) return reject(error.NotSupported, "the scheduler was shut down");
    switch (cadence) {
        c.KE_SCHEDULER_CADENCE_EVERY_TICK, c.KE_SCHEDULER_CADENCE_FIXED, c.KE_SCHEDULER_CADENCE_STARTUP, c.KE_SCHEDULER_CADENCE_SHUTDOWN => {},
        else => return reject(error.InvalidArgument, "unknown cadence"),
    }
    try s.entries.append(gpa, .{ .run = run, .user = user, .cadence = cadence });
}

fn runEntry(s: *State, entry: *Entry, dt: f32) R.Error!void {
    const number = s.sequence.fetchAdd(1, .acq_rel) + 1;
    var done: ?*abi_completion.c.ke_completion = null;
    R.check(entry.run(entry.user, dt, &done)) catch |err| {
        log.warn("a run could not start: {t}", .{err});
        return err;
    };
    const finished = done orelse return reject(error.General, "a run started without a completion");
    const result = finished.wait.?(finished);
    finished.release.?(finished);
    R.check(result) catch |err| {
        log.warn("a run failed: {t}", .{err});
        return err;
    };
    entry.completed.store(number, .release);
}

fn runCadence(s: *State, cadence: c.ke_scheduler_cadence) R.Error!void {
    for (s.entries.items) |*entry| {
        if (entry.cadence == cadence) try runEntry(s, entry, 0);
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
    s.jobs.drain.?(s.jobs);
    s.async_system.drain.?(s.async_system);
    if (!s.started) {
        s.started = true;
        try runCadence(s, c.KE_SCHEDULER_CADENCE_STARTUP);
    }
    s.accumulated = @min(s.accumulated + dt, s.fixed_dt_max_accum);
    var steps: u32 = 0;
    while (s.accumulated >= s.fixed_dt) : (steps += 1) s.accumulated -= s.fixed_dt;
    s.alpha.store(s.accumulated / s.fixed_dt, .release);
    const entries = s.entries.items;
    var i: usize = 0;
    while (i < entries.len) {
        switch (entries[i].cadence) {
            c.KE_SCHEDULER_CADENCE_EVERY_TICK => {
                try runEntry(s, &entries[i], dt);
                i += 1;
            },
            c.KE_SCHEDULER_CADENCE_FIXED => {
                var end = i;
                while (end < entries.len and entries[end].cadence == c.KE_SCHEDULER_CADENCE_FIXED) end += 1;
                for (0..steps) |_| {
                    for (entries[i..end]) |*entry| try runEntry(s, entry, s.fixed_dt);
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

/// Slot `sequence`.
fn sequence(self: ?*c.ke_scheduler) callconv(.c) u64 {
    const s = stateOf(self) orelse return 0;
    return s.sequence.load(.acquire);
}

/// Slot `completed_since`. `entries` only grows between ticks, on the thread calling tick.
fn completedSince(self: ?*c.ke_scheduler, user: ?*const anyopaque, number: u64) callconv(.c) bool {
    const s = stateOf(self) orelse return false;
    for (s.entries.items) |*entry| {
        if (@as(?*const anyopaque, entry.user) != user) continue;
        if (entry.completed.load(.acquire) < number) return false;
    }
    return true;
}

/// Slot `fixed_alpha`.
fn fixedAlpha(self: ?*c.ke_scheduler) callconv(.c) f32 {
    const s = stateOf(self) orelse return 0;
    return s.alpha.load(.acquire);
}

/// Slot `destroy` of the handle: shuts down for a caller that did not, then frees the state.
fn destroy(self: ?*c.ke_scheduler) callconv(.c) void {
    const s = stateOf(self) orelse return;
    shutdownSchedules(s) catch {};
    s.entries.deinit(gpa);
    gpa.destroy(s);
}

/// The scheduler's settings: the contract's keys, with this implementation's defaults.
const Settings = struct {
    fixed_dt: f32 = 1.0 / 60.0,
    fixed_dt_max_accum: f32 = 0.25,

    pub const ranges = .{ .fixed_dt = .{ std.math.floatMin(f64), std.math.floatMax(f64) }, .fixed_dt_max_accum = .{ std.math.floatMin(f64), std.math.floatMax(f64) } };
};

/// The factory: a scheduler with no executable, over a job and an async system it borrows.
export fn ke_scheduler_create(job_system: ?*abi_job.c.ke_job_system, async_system: ?*abi_async.c.ke_async, settings: ?*abi_settings.c.ke_settings, out_scheduler: ?*c.ke_scheduler_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_scheduler orelse return failed("ke_scheduler_create", error.InvalidArgument);
    out.* = .{};
    const jobs = job_system orelse return failed("ke_scheduler_create", reject(error.InvalidArgument, "a scheduler needs a job system"));
    const asyncs = async_system orelse return failed("ke_scheduler_create", reject(error.InvalidArgument, "a scheduler needs an async system"));
    const cfg = settings_schema.read(Settings, settings orelse return failed("ke_scheduler_create", reject(error.InvalidArgument, "a scheduler needs its settings"))) catch |err| return failed("ke_scheduler_create", err);
    const s = gpa.create(State) catch |err| return failed("ke_scheduler_create", err);
    s.* = .{
        .api = .{
            .add = &add,
            .tick = &tick,
            .shutdown = &shutdown,
            .request_exit = &requestExit,
            .exit_requested = &exitRequested,
            .sequence = &sequence,
            .completed_since = &completedSince,
            .fixed_alpha = &fixedAlpha,
        },
        .jobs = jobs,
        .async_system = asyncs,
        .fixed_dt = cfg.fixed_dt,
        .fixed_dt_max_accum = cfg.fixed_dt_max_accum,
    };
    s.api.handle = s;
    out.* = .{ .ref = &s.api, .destroy = &destroy };
    return R.ok;
}

const P = abi_part.c;

const contract_list = [_]?[*:0]const u8{"ke_scheduler"};

const scheduler_slots = [_]P.ke_part_slot{
    .{ .name = "job", .contract = "ke_job_system", .cardinality = P.KE_PART_CARDINALITY_ONE },
    .{ .name = "async", .contract = "ke_async", .cardinality = P.KE_PART_CARDINALITY_ONE },
};

const layout_slots = [_]P.ke_part_slot{
    .{ .name = "scheduler", .contract = "ke_scheduler", .cardinality = P.KE_PART_CARDINALITY_ONE },
    .{ .name = "startup", .contract = "ke_scheduler_executable", .cardinality = P.KE_PART_CARDINALITY_MANY },
    .{ .name = "every_tick", .contract = "ke_scheduler_executable", .cardinality = P.KE_PART_CARDINALITY_MANY },
    .{ .name = "fixed", .contract = "ke_scheduler_executable", .cardinality = P.KE_PART_CARDINALITY_MANY },
    .{ .name = "shutdown", .contract = "ke_scheduler_executable", .cardinality = P.KE_PART_CARDINALITY_MANY },
};

const cadence_of_slot = [_]c.ke_scheduler_cadence{
    c.KE_SCHEDULER_CADENCE_STARTUP,
    c.KE_SCHEDULER_CADENCE_EVERY_TICK,
    c.KE_SCHEDULER_CADENCE_FIXED,
    c.KE_SCHEDULER_CADENCE_SHUTDOWN,
};

fn first(b: P.ke_part_bound) ?*anyopaque {
    return if (b.count > 0) @as([*]const ?*anyopaque, @ptrCast(b.instances))[0] else null;
}

fn destroyPart(ref: ?*anyopaque) callconv(.c) void {
    destroy(@ptrCast(@alignCast(ref)));
}

/// Slot `create` of the scheduler's part: the scheduler over the job and async systems bound to it.
fn createScheduler(self: ?*const P.ke_part, bound_in: ?*const P.ke_part_bound, settings: ?*abi_settings.c.ke_settings, out_instance: ?*P.ke_owner) callconv(.c) abi_result.c.ke_result {
    const out = out_instance orelse return R.code(error.InvalidArgument);
    out.* = .{};
    if (self == null) return R.code(error.InvalidArgument);
    const bound: [*]const P.ke_part_bound = @ptrCast(bound_in orelse return R.code(error.InvalidArgument));
    var handle: c.ke_scheduler_handle = .{};
    const made = ke_scheduler_create(@ptrCast(@alignCast(first(bound[0]))), @ptrCast(@alignCast(first(bound[1]))), settings, &handle);
    if (made != R.ok) return made;
    out.* = .{ .ref = handle.ref, .destroy = &destroyPart };
    return R.ok;
}

/// One executable of a cadence slot, with where the composition placed it among all of them.
const Placed = struct { position: usize, cadence: c.ke_scheduler_cadence, executable: *const c.ke_scheduler_executable };

/// The `destroy` of the layout's owner: runs the scheduler's shutdown executables while they still exist; the
/// scheduler's own destroy then runs nothing more.
fn shutdownLayout(ref: ?*anyopaque) callconv(.c) void {
    const sched: *c.ke_scheduler = @ptrCast(@alignCast(ref orelse return));
    const ended = shutdown(sched);
    if (ended != R.ok) log.warn("the scheduler's shutdown failed with result code {d}", .{ended});
}

/// Slot `create` of the layout's part: adds every executable of the cadence slots to the scheduler bound to it, in
/// the order of their positions, each with its slot's cadence, the one order a tick runs them in.
fn createLayout(self: ?*const P.ke_part, bound_in: ?*const P.ke_part_bound, settings: ?*abi_settings.c.ke_settings, out_instance: ?*P.ke_owner) callconv(.c) abi_result.c.ke_result {
    _ = settings;
    const out = out_instance orelse return R.code(error.InvalidArgument);
    out.* = .{};
    if (self == null) return R.code(error.InvalidArgument);
    const bound: [*]const P.ke_part_bound = @ptrCast(bound_in orelse return R.code(error.InvalidArgument));
    const sched: *c.ke_scheduler = @ptrCast(@alignCast(first(bound[0]) orelse return R.code(error.InvalidArgument)));
    var placed: std.ArrayList(Placed) = .empty;
    defer placed.deinit(gpa);
    for (cadence_of_slot, 1..) |cadence, k| {
        const b = bound[k];
        if (b.count == 0) continue;
        const instances = @as([*]const ?*anyopaque, @ptrCast(b.instances))[0..b.count];
        const positions = @as([*]const usize, @ptrCast(b.positions))[0..b.count];
        for (instances, positions) |instance, position| {
            placed.append(gpa, .{ .position = position, .cadence = cadence, .executable = @ptrCast(@alignCast(instance orelse return R.code(error.InvalidArgument))) }) catch |err| return R.code(err);
        }
    }
    std.sort.insertion(Placed, placed.items, {}, struct {
        fn lessThan(_: void, x: Placed, y: Placed) bool {
            return x.position < y.position;
        }
    }.lessThan);
    for (placed.items) |p| {
        const added = add(sched, p.executable.run, p.executable.user, p.cadence);
        if (added != R.ok) return added;
    }
    out.* = .{ .ref = sched, .destroy = &shutdownLayout };
    return R.ok;
}

const parts = [_]P.ke_part{
    .{
        .name = "scheduler",
        .provides = &contract_list[0],
        .provides_count = contract_list.len,
        .slots = &scheduler_slots[0],
        .slot_count = scheduler_slots.len,
        .create = &createScheduler,
        .set_log = @ptrCast(&@import("log").Destination("ke_scheduler").setLogCallback),
    },
    .{
        .name = "scheduler_layout",
        .slots = &layout_slots[0],
        .slot_count = layout_slots.len,
        .create = &createLayout,
        .set_log = @ptrCast(&@import("log").Destination("ke_scheduler").setLogCallback),
    },
};

/// The library's parts.
export fn ke_scheduler_parts(out_count: ?*usize) callconv(.c) ?*const P.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

const testing = std.testing;

var zero_dt = settings_schema.Fixed.init(&.{.{ .key = "fixed_dt", .value = .{ .double = 0 } }});
var zero_accum = settings_schema.Fixed.init(&.{.{ .key = "fixed_dt_max_accum", .value = .{ .double = 0 } }});
var test_settings = settings_schema.Fixed.init(&.{ .{ .key = "fixed_dt", .value = .{ .double = 0.25 } }, .{ .key = "fixed_dt_max_accum", .value = .{ .double = 1.0 } } });

const Log = struct {
    letters: [32]u8 = undefined,
    dts: [32]f32 = undefined,
    count: usize = 0,

    fn text(l: *const Log) []const u8 {
        return l.letters[0..l.count];
    }
};

const zsub = @import("zsub");

/// An executable that writes its letter and dt into a shared log, or fails when told to.
const Fake = struct {
    log: *Log,
    letter: u8,
    fails: bool = false,
    done: abi_completion.c.ke_completion = undefined,
    outcome: abi_result.c.ke_result = R.ok,

    fn init(f: *Fake, log_to: *Log, letter: u8) void {
        f.* = .{ .log = log_to, .letter = letter };
    }
};

fn donePoll(c_in: ?*abi_completion.c.ke_completion, out: ?*abi_result.c.ke_result) callconv(.c) bool {
    if (out) |o| o.* = @as(*Fake, @ptrCast(@alignCast(c_in.?.handle.?))).outcome;
    return true;
}

fn doneWait(c_in: ?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result {
    return @as(*Fake, @ptrCast(@alignCast(c_in.?.handle.?))).outcome;
}

fn doneRelease(_: ?*abi_completion.c.ke_completion) callconv(.c) void {}

fn fakeRun(user: ?*anyopaque, dt: f32, out: ?*?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result {
    const f: *Fake = @ptrCast(@alignCast(user.?));
    f.done = .{ .handle = f, .poll = &donePoll, .wait = &doneWait, .release = &doneRelease };
    out.?.* = &f.done;
    if (f.fails) {
        f.outcome = R.code(error.Io);
        return R.ok;
    }
    f.outcome = R.ok;
    f.log.letters[f.log.count] = f.letter;
    f.log.dts[f.log.count] = dt;
    f.log.count += 1;
    return R.ok;
}

const Rig = struct {
    handle: c.ke_scheduler_handle,
    sched: *c.ke_scheduler,
    jobs: zsub.For(abi_job.c.ke_job_system) = undefined,
    asyncs: zsub.For(abi_async.c.ke_async) = undefined,
    log: Log = .{},
    fakes: [6]Fake = undefined,

    fn init(r: *Rig, cadences: []const c.ke_scheduler_cadence) !void {
        r.log = .{};
        try r.jobs.init();
        try r.asyncs.init();
        try R.check(ke_scheduler_create(r.jobs.api(), r.asyncs.api(), &test_settings.api, &r.handle));
        r.sched = r.handle.ref.?;
        for (cadences, 0..) |cadence, i| {
            r.fakes[i].init(&r.log, @intCast('a' + i));
            try R.check(r.sched.add.?(r.sched, &fakeRun, &r.fakes[i], cadence));
        }
    }

    fn deinit(r: *Rig) void {
        r.handle.destroy.?(r.sched);
        r.asyncs.deinit();
        r.jobs.deinit();
    }

    fn tick(r: *Rig, dt: f32) !void {
        try R.check(r.sched.tick.?(r.sched, dt));
    }
};

const every = c.KE_SCHEDULER_CADENCE_EVERY_TICK;
const fixed = c.KE_SCHEDULER_CADENCE_FIXED;
const startup = c.KE_SCHEDULER_CADENCE_STARTUP;
const shut = c.KE_SCHEDULER_CADENCE_SHUTDOWN;

test "the startup executables run once, before every other schedule of the first tick, with a dt of zero" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, startup });
    defer rig.deinit();
    try rig.tick(0.1);
    try rig.tick(0.1);
    try testing.expectEqualStrings("baa", rig.log.text());
    try testing.expectEqual(0, rig.log.dts[0]);
    try testing.expectEqual(0.1, rig.log.dts[1]);
}

test "consecutive fixed executables run together, in order, once per fixed step, with the fixed dt" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, fixed, fixed, every });
    defer rig.deinit();
    try rig.tick(0.5);
    try testing.expectEqualStrings("abcbcd", rig.log.text());
    try testing.expectEqual(0.25, rig.log.dts[1]);
}

test "the fixed executables accumulate at their own rate, and a tick shorter than the step takes none" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{fixed});
    defer rig.deinit();
    try rig.tick(0.1);
    try testing.expectEqualStrings("", rig.log.text());
    try rig.tick(0.2);
    try testing.expectEqualStrings("a", rig.log.text());
}

test "a huge tick is capped so the fixed executables cannot spiral" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{fixed});
    defer rig.deinit();
    try rig.tick(100);
    try testing.expectEqual(4, rig.log.count);
}

test "the shutdown executables run once when the scheduler shuts down after a tick, and a tick after it is refused" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, shut });
    defer rig.deinit();
    try rig.tick(0);
    try R.check(rig.sched.shutdown.?(rig.sched));
    try R.check(rig.sched.shutdown.?(rig.sched));
    try testing.expectEqualStrings("ab", rig.log.text());
    try testing.expectEqual(R.code(error.NotSupported), rig.sched.tick.?(rig.sched, 0));
}

test "destroying a scheduler that ticked runs its shutdown executables, and one that never ticked runs none" {
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

test "an executable that fails the tick keeps the later executables from running" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, every });
    defer rig.deinit();
    rig.fakes[0].fails = true;
    try testing.expectEqual(R.code(error.Io), rig.sched.tick.?(rig.sched, 0));
    try testing.expectEqualStrings("", rig.log.text());
}

test "an unknown cadence, a null run and a negative dt are refused" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{});
    defer rig.deinit();
    var fake: Fake = undefined;
    fake.init(&rig.log, 'x');
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.add.?(rig.sched, &fakeRun, &fake, 9));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.add.?(rig.sched, null, &fake, every));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.tick.?(rig.sched, -1));
}

test "each run takes the next number, and a failed run does not complete" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, every });
    defer rig.deinit();
    try testing.expectEqual(0, rig.sched.sequence.?(rig.sched));
    try rig.tick(0);
    try testing.expectEqual(2, rig.sched.sequence.?(rig.sched));
    rig.fakes[1].fails = true;
    try testing.expectEqual(R.code(error.Io), rig.sched.tick.?(rig.sched, 0));
    try testing.expectEqual(4, rig.sched.sequence.?(rig.sched));
    try testing.expect(!rig.sched.completed_since.?(rig.sched, &rig.fakes[1], 4));
}

test "an executable completes a sequence once a run numbered from it completed, and one never added already has" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{ every, fixed });
    defer rig.deinit();
    var stranger: u8 = 0;
    try testing.expect(rig.sched.completed_since.?(rig.sched, &stranger, 1));
    try rig.tick(0);
    const stamp = rig.sched.sequence.?(rig.sched);
    try testing.expect(!rig.sched.completed_since.?(rig.sched, &rig.fakes[1], stamp));
    try rig.tick(0.1);
    try testing.expect(!rig.sched.completed_since.?(rig.sched, &rig.fakes[1], stamp));
    try rig.tick(0.2);
    try testing.expect(rig.sched.completed_since.?(rig.sched, &rig.fakes[1], stamp));
}

test "every tick drains the job and async systems first, and fixed_alpha is what the fixed steps left over" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{fixed});
    defer rig.deinit();
    try rig.tick(0.375);
    try rig.jobs.received(.drain).times(1);
    try rig.asyncs.received(.drain).times(1);
    try testing.expectEqual(@as(f32, 0.5), rig.sched.fixed_alpha.?(rig.sched));
}

test "a request to exit is recorded and read back, and a fresh scheduler has none" {
    var rig: Rig = .{ .handle = undefined, .sched = undefined };
    try rig.init(&.{});
    defer rig.deinit();
    try testing.expect(!rig.sched.exit_requested.?(rig.sched));
    rig.sched.request_exit.?(rig.sched);
    try testing.expect(rig.sched.exit_requested.?(rig.sched));
}

test "a fixed dt or a catch-up budget that is not greater than zero, no config, or a missing system is refused and leaves the handle zeroed" {
    var jobs: zsub.For(abi_job.c.ke_job_system) = undefined;
    try jobs.init();
    defer jobs.deinit();
    var asyncs: zsub.For(abi_async.c.ke_async) = undefined;
    try asyncs.init();
    defer asyncs.deinit();
    var handle: c.ke_scheduler_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(jobs.api(), asyncs.api(), &zero_dt.api, &handle));
    try testing.expectEqual(null, handle.ref);
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(jobs.api(), asyncs.api(), &zero_accum.api, &handle));
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(jobs.api(), asyncs.api(), null, &handle));
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(null, asyncs.api(), &test_settings.api, &handle));
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(jobs.api(), null, &test_settings.api, &handle));
}

test "a slot given no scheduler refuses" {
    try testing.expectEqual(R.code(error.InvalidArgument), tick(null, 0));
    try testing.expectEqual(R.code(error.InvalidArgument), shutdown(null));
    try testing.expect(!exitRequested(null));
}

const Executable = struct {
    log: *Log,
    letter: u8,
    done: abi_completion.c.ke_completion = .{ .poll = &executablePoll, .wait = &executableWait, .release = &doneRelease },
    as_added: c.ke_scheduler_executable = undefined,

    fn bind(e: *Executable) *c.ke_scheduler_executable {
        e.as_added = .{ .run = &Executable.run, .user = e };
        return &e.as_added;
    }

    fn run(user: ?*anyopaque, dt: f32, out: ?*?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result {
        const e: *Executable = @ptrCast(@alignCast(user.?));
        e.log.letters[e.log.count] = e.letter;
        e.log.dts[e.log.count] = dt;
        e.log.count += 1;
        out.?.* = &e.done;
        return R.ok;
    }
};

fn executablePoll(_: ?*abi_completion.c.ke_completion, out: ?*abi_result.c.ke_result) callconv(.c) bool {
    if (out) |o| o.* = R.ok;
    return true;
}

fn executableWait(_: ?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result {
    return R.ok;
}

test "the layout's part adds every executable of its cadence slots in the order of their positions, and its owner shuts the scheduler down" {
    var jobs: zsub.For(abi_job.c.ke_job_system) = undefined;
    try jobs.init();
    defer jobs.deinit();
    var asyncs: zsub.For(abi_async.c.ke_async) = undefined;
    try asyncs.init();
    defer asyncs.deinit();
    var log_of: Log = .{};
    var start = Executable{ .log = &log_of, .letter = 's' };
    var pre = Executable{ .log = &log_of, .letter = 'p' };
    var step = Executable{ .log = &log_of, .letter = 'f' };
    var update = Executable{ .log = &log_of, .letter = 'u' };
    var end = Executable{ .log = &log_of, .letter = 'e' };
    const job = [_]?*anyopaque{jobs.api()};
    const async_one = [_]?*anyopaque{asyncs.api()};
    const only = [_]usize{0};
    const made_bound = [_]P.ke_part_bound{
        .{ .instances = @ptrCast(&job), .positions = &only[0], .count = 1 },
        .{ .instances = @ptrCast(&async_one), .positions = &only[0], .count = 1 },
    };
    var count: usize = 0;
    const all: [*]const P.ke_part = @ptrCast(ke_scheduler_parts(&count).?);
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqual(@as(usize, 2), all[0].slot_count);
    try testing.expectEqual(@as(usize, 5), all[1].slot_count);
    var made: P.ke_owner = undefined;
    try R.check(all[0].create.?(&all[0], &made_bound[0], &test_settings.api, &made));
    const sched: *c.ke_scheduler = @ptrCast(@alignCast(made.ref.?));
    const scheduler_one = [_]?*anyopaque{sched};
    const startups = [_]?*anyopaque{start.bind()};
    const ticks = [_]?*anyopaque{ pre.bind(), update.bind() };
    const fixeds = [_]?*anyopaque{step.bind()};
    const shutdowns = [_]?*anyopaque{end.bind()};
    const start_at = [_]usize{0};
    const ticks_at = [_]usize{ 1, 3 };
    const fixed_at = [_]usize{2};
    const end_at = [_]usize{4};
    const layout_bound = [_]P.ke_part_bound{
        .{ .instances = @ptrCast(&scheduler_one), .positions = &only[0], .count = 1 },
        .{ .instances = @ptrCast(&startups), .positions = &start_at[0], .count = 1 },
        .{ .instances = @ptrCast(&ticks), .positions = &ticks_at[0], .count = 2 },
        .{ .instances = @ptrCast(&fixeds), .positions = &fixed_at[0], .count = 1 },
        .{ .instances = @ptrCast(&shutdowns), .positions = &end_at[0], .count = 1 },
    };
    var layout: P.ke_owner = undefined;
    try R.check(all[1].create.?(&all[1], &layout_bound[0], null, &layout));
    try R.check(sched.tick.?(sched, 0.25));
    try testing.expect(sched.completed_since.?(sched, &update, 1));
    try testing.expect(!sched.completed_since.?(sched, &update, sched.sequence.?(sched) + 1));
    layout.destroy.?(layout.ref);
    try testing.expectEqualStrings("spfue", log_of.text());
    made.destroy.?(made.ref);
    try testing.expectEqualStrings("spfue", log_of.text());
}

test "nothing the scheduler allocated is left behind" {
    try heap.expectNoLeaks();
}

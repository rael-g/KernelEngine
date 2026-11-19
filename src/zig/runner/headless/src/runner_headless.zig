//! The `ke_runner` contract with no window: a run ticks the scheduler a fixed number of frames with a fixed dt,
//! reporting before each frame the key transitions a script gives it, as a window reports its events.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_runner_headless").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const abi_input = @import("abi_input");
const abi_part = @import("abi_part");
const abi_result = @import("abi_result");
const abi_runner = @import("abi_runner");
const abi_scheduler = @import("abi_scheduler");
const abi_settings = @import("abi_settings");
const heap = @import("heap");
const input_names = @import("input_names");
const part = @import("part");
const settings_schema = @import("settings_schema");

const R = @import("result").Result(.{});
const log = std.log.scoped(.runner_headless);
const gpa = heap.gpa;

const c = abi_runner.c;

/// One key transition of the script, reported before the frame `frame` ticks.
const Entry = struct { frame: u64, key: c_int, action: c_int };

/// The state behind the handle: what it ticks and feeds, how, and the script sorted by frame.
const State = struct {
    api: c.ke_runner,
    scheduler: *abi_scheduler.c.ke_scheduler,
    input: *abi_input.c.ke_input,
    frames: u64,
    dt: f32,
    script: []Entry,
};

fn stateOf(self: ?*c.ke_runner) ?*State {
    return @alignCast(@fieldParentPtr("api", self orelse return null));
}

fn reject(err: R.Error, comptime why: []const u8, args: anytype) R.Error {
    log.warn(why, args);
    return err;
}

fn failed(comptime slot: []const u8, err: R.Error) abi_result.c.ke_result {
    log.warn(slot ++ " failed: {t}", .{err});
    return R.code(err);
}

/// Slot `run`: frame by frame, reports the frame's entries, then ticks; ends after the last frame or once the
/// program is asked to end.
fn run(self: ?*c.ke_runner) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("run", error.InvalidArgument);
    const sched = s.scheduler;
    var next: usize = 0;
    var frame: u64 = 0;
    while (frame < s.frames and !sched.exit_requested.?(sched)) : (frame += 1) {
        while (next < s.script.len and s.script[next].frame == frame) : (next += 1) {
            s.input.on_key.?(s.input, s.script[next].key, s.script[next].action);
        }
        const ticked = sched.tick.?(sched, s.dt);
        if (ticked != R.ok) return ticked;
    }
    return R.ok;
}

/// Slot `destroy` of the handle.
fn destroy(self: ?*c.ke_runner) callconv(.c) void {
    const s = stateOf(self) orelse return;
    gpa.free(s.script);
    gpa.destroy(s);
}

/// The runner's settings, with this implementation's defaults; the script is the child `script`.
const Settings = struct {
    frames: u64 = 60,
    dt: f32 = 1.0 / 60.0,

    pub const ranges = .{ .frames = .{ 0, std.math.maxInt(i64) }, .dt = .{ std.math.floatMin(f64), std.math.floatMax(f64) } };
    pub const children = .{"script"};
};

/// One entry of the script, as written.
const Written = struct {
    frame: ?u64 = null,
    key: ?[:0]const u8 = null,
    action: ?enum { down, up } = null,
};

/// The entries the children of `script` describe, sorted by frame, those of one frame in the order
/// written.
fn parse(script: *abi_settings.c.ke_settings) R.Error![]Entry {
    const Collect = struct {
        script: *abi_settings.c.ke_settings,
        entries: std.ArrayList(Entry) = .empty,
        failure: ?R.Error = null,

        fn each(name: ?[*:0]const u8, ctx: ?*anyopaque) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (self.failure == null) self.add(name.?) catch |err| {
                self.failure = err;
            };
        }

        fn add(self: *@This(), name: [*:0]const u8) R.Error!void {
            var child: ?*abi_settings.c.ke_settings = null;
            try R.check(self.script.child.?(self.script, name, &child));
            const w = try settings_schema.read(Written, child.?);
            const frame = w.frame orelse return reject(error.InvalidArgument, "script entry {s} has no frame", .{name});
            const key_name = w.key orelse return reject(error.InvalidArgument, "script entry {s} has no key", .{name});
            const written = w.action orelse return reject(error.InvalidArgument, "script entry {s} has no action", .{name});
            const key = input_names.key(key_name) orelse return reject(error.InvalidArgument, "script entry {s}: '{s}' names no key", .{ name, key_name });
            const action: c_int = switch (written) {
                .down => abi_input.c.KE_INPUT_ACTION_PRESS,
                .up => abi_input.c.KE_INPUT_ACTION_RELEASE,
            };
            try self.entries.append(gpa, .{ .frame = frame, .key = key, .action = action });
        }
    };
    var collect: Collect = .{ .script = script };
    errdefer collect.entries.deinit(gpa);
    try R.check(script.for_each_child.?(script, Collect.each, &collect));
    if (collect.failure) |err| return err;
    const sorted = try collect.entries.toOwnedSlice(gpa);
    std.sort.insertion(Entry, sorted, {}, struct {
        fn lessThan(_: void, a_: Entry, b_: Entry) bool {
            return a_.frame < b_.frame;
        }
    }.lessThan);
    return sorted;
}

/// The factory: a runner over a scheduler and an input it borrows.
export fn ke_runner_headless_create(scheduler: ?*abi_scheduler.c.ke_scheduler, input: ?*abi_input.c.ke_input, settings: ?*abi_settings.c.ke_settings, out_runner: ?*c.ke_runner_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_runner orelse return failed("ke_runner_headless_create", error.InvalidArgument);
    out.* = .{};
    const sched = scheduler orelse return failed("ke_runner_headless_create", reject(error.InvalidArgument, "a runner needs a scheduler", .{}));
    const in = input orelse return failed("ke_runner_headless_create", reject(error.InvalidArgument, "a runner needs an input", .{}));
    const given = settings orelse return failed("ke_runner_headless_create", reject(error.InvalidArgument, "a runner needs its settings", .{}));
    const cfg = settings_schema.read(Settings, given) catch |err| return failed("ke_runner_headless_create", err);
    var script_settings: ?*abi_settings.c.ke_settings = null;
    R.check(given.child.?(given, "script", &script_settings)) catch |err| return failed("ke_runner_headless_create", err);
    const script = parse(script_settings.?) catch |err| return failed("ke_runner_headless_create", err);
    const s = gpa.create(State) catch |err| {
        gpa.free(script);
        return failed("ke_runner_headless_create", err);
    };
    s.* = .{ .api = .{ .run = &run }, .scheduler = sched, .input = in, .frames = cfg.frames, .dt = cfg.dt, .script = script };
    s.api.handle = s;
    out.* = .{ .ref = &s.api, .destroy = &destroy };
    return R.ok;
}

const parts = [_]abi_part.c.ke_part{
    part.of(ke_runner_headless_create, .{ .name = "runner_headless", .slots = &.{ "scheduler", "input" }, .set_log = @ptrCast(&@import("log").Destination("ke_runner_headless").setLogCallback) }),
};

/// The library's parts.
export fn ke_runner_headless_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

const testing = std.testing;
const zsub = @import("zsub");

/// What each tick saw: how many key transitions the input had received when it ran, and the tick's dt.
const Seen = struct {
    keys_at: [16]usize = undefined,
    dts: [16]f32 = undefined,
    ticks: usize = 0,
    exit_after: usize = std.math.maxInt(usize),
    fail_at: usize = std.math.maxInt(usize),
};

var seen: Seen = .{};
var watched: *zsub.For(abi_input.c.ke_input) = undefined;

fn tickSeen(args: zsub.For(abi_scheduler.c.ke_scheduler).Args(.tick)) abi_result.c.ke_result {
    if (seen.ticks == seen.fail_at) return R.code(error.Io);
    seen.keys_at[seen.ticks] = watched.received(.on_key).calls;
    seen.dts[seen.ticks] = args[1];
    seen.ticks += 1;
    return R.ok;
}

fn exitSeen(_: zsub.For(abi_scheduler.c.ke_scheduler).Args(.exit_requested)) bool {
    return seen.ticks >= seen.exit_after;
}

fn keyIs(comptime key: c_int, comptime action: c_int) fn (zsub.For(abi_input.c.ke_input).Args(.on_key)) bool {
    return struct {
        fn matches(args: zsub.For(abi_input.c.ke_input).Args(.on_key)) bool {
            return args[1] == key and args[2] == action;
        }
    }.matches;
}

const Rig = struct {
    sched: zsub.For(abi_scheduler.c.ke_scheduler) = undefined,
    input: zsub.For(abi_input.c.ke_input) = undefined,
    handle: c.ke_runner_handle = undefined,

    fn init(r: *Rig, pairs: []const settings_schema.Pair) !void {
        return r.initTree(pairs, &.{});
    }

    fn initTree(r: *Rig, pairs: []const settings_schema.Pair, children: []const settings_schema.Child) !void {
        seen = .{};
        try r.sched.init();
        try r.input.init();
        watched = &r.input;
        _ = r.sched.when(.tick).does(tickSeen);
        _ = r.sched.when(.exit_requested).does(exitSeen);
        var settings = settings_schema.Fixed.tree(pairs, children);
        try R.check(ke_runner_headless_create(r.sched.api(), r.input.api(), &settings.api, &r.handle));
    }

    fn deinit(r: *Rig) void {
        r.handle.destroy.?(r.handle.ref);
        r.input.deinit();
        r.sched.deinit();
    }

    fn run(r: *Rig) abi_result.c.ke_result {
        return r.handle.ref.?.run.?(r.handle.ref);
    }
};

test "a run ticks the scheduler the frames it was given, each with the dt it was given" {
    var rig: Rig = .{};
    try rig.init(&.{ .{ .key = "frames", .value = .{ .int = 3 } }, .{ .key = "dt", .value = .{ .double = 0.5 } } });
    defer rig.deinit();
    try R.check(rig.run());
    try testing.expectEqual(@as(usize, 3), seen.ticks);
    try testing.expectEqualSlices(f32, &.{ 0.5, 0.5, 0.5 }, seen.dts[0..3]);
}

test "each scripted transition reaches the input before its frame ticks, in the order written" {
    var rig: Rig = .{};
    var e0 = entry(2, "W", "up");
    var e1 = entry(0, "W", "down");
    var e2 = entry(0, "Space", "down");
    var e3 = entry(3, "Escape", "down");
    var script = settings_schema.Fixed.tree(&.{}, &.{ .{ .name = "0", .settings = &e0 }, .{ .name = "1", .settings = &e1 }, .{ .name = "2", .settings = &e2 }, .{ .name = "3", .settings = &e3 } });
    try rig.initTree(&.{.{ .key = "frames", .value = .{ .int = 4 } }}, &.{.{ .name = "script", .settings = &script }});
    defer rig.deinit();
    try R.check(rig.run());
    try testing.expectEqualSlices(usize, &.{ 2, 2, 3, 4 }, seen.keys_at[0..4]);
    try rig.input.received(.on_key).where(keyIs(abi_input.c.KE_KEY_W, abi_input.c.KE_INPUT_ACTION_PRESS)).times(1);
    try rig.input.received(.on_key).where(keyIs(abi_input.c.KE_KEY_W, abi_input.c.KE_INPUT_ACTION_RELEASE)).times(1);
    try rig.input.received(.on_key).where(keyIs(abi_input.c.KE_KEY_ESCAPE, abi_input.c.KE_INPUT_ACTION_PRESS)).times(1);
}

test "a run ends early once the program is asked to end" {
    var rig: Rig = .{};
    try rig.init(&.{.{ .key = "frames", .value = .{ .int = 10 } }});
    defer rig.deinit();
    seen.exit_after = 2;
    try R.check(rig.run());
    try testing.expectEqual(@as(usize, 2), seen.ticks);
}

test "a tick that fails ends the run with its code" {
    var rig: Rig = .{};
    try rig.init(&.{.{ .key = "frames", .value = .{ .int = 10 } }});
    defer rig.deinit();
    seen.fail_at = 1;
    try testing.expectEqual(R.code(error.Io), rig.run());
    try testing.expectEqual(@as(usize, 1), seen.ticks);
}

fn entry(comptime frame: i64, comptime key: [:0]const u8, comptime action: [:0]const u8) settings_schema.Fixed {
    return settings_schema.Fixed.init(&.{ .{ .key = "frame", .value = .{ .int = frame } }, .{ .key = "key", .value = .{ .string = key } }, .{ .key = "action", .value = .{ .string = action } } });
}

test "a script entry missing a field, naming no key or action, or holding another key, a dt not greater than zero or a missing dependency is refused and leaves the handle zeroed" {
    var sched: zsub.For(abi_scheduler.c.ke_scheduler) = undefined;
    try sched.init();
    defer sched.deinit();
    var input: zsub.For(abi_input.c.ke_input) = undefined;
    try input.init();
    defer input.deinit();
    var no_action = settings_schema.Fixed.init(&.{ .{ .key = "frame", .value = .{ .int = 0 } }, .{ .key = "key", .value = .{ .string = "W" } } });
    var no_frame = settings_schema.Fixed.init(&.{ .{ .key = "key", .value = .{ .string = "W" } }, .{ .key = "action", .value = .{ .string = "down" } } });
    var lower = entry(0, "w", "down");
    var held = entry(0, "W", "held");
    var extra = settings_schema.Fixed.init(&.{ .{ .key = "frame", .value = .{ .int = 0 } }, .{ .key = "key", .value = .{ .string = "W" } }, .{ .key = "action", .value = .{ .string = "down" } }, .{ .key = "speed", .value = .{ .int = 1 } } });
    const bad = [_]*settings_schema.Fixed{ &no_action, &no_frame, &lower, &held, &extra };
    var handle: c.ke_runner_handle = undefined;
    for (bad) |one| {
        var script = settings_schema.Fixed.tree(&.{}, &.{.{ .name = "0", .settings = one }});
        var settings = settings_schema.Fixed.tree(&.{}, &.{.{ .name = "script", .settings = &script }});
        try testing.expectEqual(R.code(error.InvalidArgument), ke_runner_headless_create(sched.api(), input.api(), &settings.api, &handle));
        try testing.expectEqual(null, handle.ref);
    }
    const refused = [_][]const settings_schema.Pair{
        &.{.{ .key = "dt", .value = .{ .double = 0 } }},
        &.{.{ .key = "speed", .value = .{ .int = 1 } }},
    };
    for (refused) |pairs| {
        var settings = settings_schema.Fixed.init(pairs);
        try testing.expectEqual(R.code(error.InvalidArgument), ke_runner_headless_create(sched.api(), input.api(), &settings.api, &handle));
        try testing.expectEqual(null, handle.ref);
    }
    var empty = settings_schema.Fixed.init(&.{});
    try testing.expectEqual(R.code(error.InvalidArgument), ke_runner_headless_create(null, input.api(), &empty.api, &handle));
    try testing.expectEqual(R.code(error.InvalidArgument), ke_runner_headless_create(sched.api(), null, &empty.api, &handle));
    try testing.expectEqual(R.code(error.InvalidArgument), ke_runner_headless_create(sched.api(), input.api(), null, &handle));
}

test "the library's part provides ke_runner from a scheduler and an input" {
    var count: usize = 0;
    const p = ke_runner_headless_parts(&count).?;
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqualStrings("runner_headless", std.mem.span(p.name.?));
    try testing.expectEqualStrings("ke_runner", std.mem.span(p.provides.?));
    try testing.expectEqual(@as(usize, 2), p.slot_count);
    try testing.expect(p.set_log != null);
}

test "a slot given no runner refuses" {
    try testing.expectEqual(R.code(error.InvalidArgument), run(null));
}

test "nothing the runner allocated is left behind" {
    try heap.expectNoLeaks();
}

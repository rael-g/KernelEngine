//! The behaviour every `ke_async` promises, run by the tests of each implementation against a
//! system it creates with a submit_capacity of one.

const std = @import("std");
const abi_async = @import("abi_async");
const abi_completion = @import("abi_completion");
const abi_result = @import("abi_result");

const c = abi_async.c;
const Completion = abi_completion.c.ke_completion;
const Result = abi_result.c.ke_result;
const ok = abi_result.c.KE_OK;
const not_found = abi_result.c.KE_RESULT_NOT_FOUND;
const testing = std.testing;

pub const Create = *const fn () anyerror!c.ke_async_handle;

/// A completion of another origin that the test finishes by hand.
const Foreign = struct {
    api: Completion,
    done: std.atomic.Value(bool) = .init(false),
    result: Result = ok,

    fn init(self: *Foreign) void {
        self.* = .{ .api = .{ .handle = self, .poll = poll, .wait = wait, .release = release } };
    }

    fn complete(self: *Foreign, result: Result) void {
        self.result = result;
        self.done.store(true, .release);
    }

    fn poll(c_in: ?*Completion, out: ?*Result) callconv(.c) bool {
        const self: *Foreign = @ptrCast(@alignCast(c_in.?.handle));
        if (!self.done.load(.acquire)) return false;
        if (out) |o| o.* = self.result;
        return true;
    }

    fn wait(c_in: ?*Completion) callconv(.c) Result {
        const self: *Foreign = @ptrCast(@alignCast(c_in.?.handle));
        while (!self.done.load(.acquire)) std.Thread.yield() catch {};
        return self.result;
    }

    fn release(_: ?*Completion) callconv(.c) void {}
};

const Probe = struct {
    code: Result = ok,
    ran: std.atomic.Value(u32) = .init(0),
    started: std.atomic.Value(bool) = .init(false),
    saw_cancel: std.atomic.Value(bool) = .init(false),
    deps: [2]Result = .{ ok, ok },
    dep_count: u32 = 0,
};

fn body(data: ?*anyopaque, ctx: ?*c.ke_async_ctx) callconv(.c) Result {
    const p: *Probe = @ptrCast(@alignCast(data.?));
    _ = p.ran.fetchAdd(1, .acq_rel);
    p.dep_count = ctx.?.dep_count;
    for (0..ctx.?.dep_count) |i| p.deps[i] = ctx.?.dep_results.?[i];
    return p.code;
}

fn untilCancelled(data: ?*anyopaque, ctx: ?*c.ke_async_ctx) callconv(.c) Result {
    const p: *Probe = @ptrCast(@alignCast(data.?));
    p.started.store(true, .release);
    while (!ctx.?.cancelled.?(ctx)) std.Thread.yield() catch {};
    p.saw_cancel.store(true, .release);
    return abi_result.c.KE_RESULT_CANCELLED;
}

fn submit(a: *c.ke_async, f: c.ke_async_fn, probe: *Probe, deps: []const ?*Completion) !*Completion {
    var out: ?*Completion = null;
    try testing.expectEqual(ok, a.submit.?(a, "op", f, probe, deps.ptr, @intCast(deps.len), &out));
    return out.?;
}

fn finish(done: *Completion) Result {
    const r = done.wait.?(done);
    done.release.?(done);
    return r;
}

fn anOperationCarriesWhatItReturned(a: *c.ke_async) !void {
    var p: Probe = .{ .code = not_found };
    try testing.expectEqual(not_found, finish(try submit(a, body, &p, &.{})));
    try testing.expectEqual(@as(u32, 1), p.ran.load(.acquire));
}

fn anOperationSeesWhatItsDependenciesFinishedWith(a: *c.ke_async) !void {
    var first: Probe = .{ .code = not_found };
    var foreign: Foreign = undefined;
    foreign.init();
    const dep = try submit(a, body, &first, &.{});
    var p: Probe = .{};
    const op = try submit(a, body, &p, &.{ dep, &foreign.api });
    a.drain.?(a);
    foreign.complete(ok);
    try testing.expectEqual(ok, finish(op));
    dep.release.?(dep);
    try testing.expectEqual(@as(u32, 2), p.dep_count);
    try testing.expectEqual(not_found, p.deps[0]);
    try testing.expectEqual(ok, p.deps[1]);
}

fn anOperationCancelledBeforeItStartsFinishesCancelledWithoutRunning(a: *c.ke_async) !void {
    var foreign: Foreign = undefined;
    foreign.init();
    var p: Probe = .{};
    const op = try submit(a, body, &p, &.{&foreign.api});
    try testing.expectEqual(ok, a.cancel.?(a, op));
    foreign.complete(ok);
    try testing.expectEqual(abi_result.c.KE_RESULT_CANCELLED, finish(op));
    try testing.expectEqual(@as(u32, 0), p.ran.load(.acquire));
}

const Canceller = struct { a: *c.ke_async, op: *Completion, probe: *Probe, code: Result = ok };

fn cancelOnceStarted(k: *Canceller) void {
    while (!k.probe.started.load(.acquire)) std.Thread.yield() catch {};
    k.code = k.a.cancel.?(k.a, k.op);
}

fn aRunningOperationSeesTheCancellation(a: *c.ke_async) !void {
    var p: Probe = .{};
    const op = try submit(a, untilCancelled, &p, &.{});
    var k: Canceller = .{ .a = a, .op = op, .probe = &p };
    const t = try std.Thread.spawn(.{}, cancelOnceStarted, .{&k});
    const r = finish(op);
    t.join();
    try testing.expectEqual(ok, k.code);
    try testing.expectEqual(abi_result.c.KE_RESULT_CANCELLED, r);
    try testing.expect(p.saw_cancel.load(.acquire));
}

const Outside = struct { a: *c.ke_async, probe: *Probe, first: ?*Completion = null, codes: [2]Result = .{ ok, ok } };

fn submitTwiceFromOutside(o: *Outside) void {
    var second: ?*Completion = null;
    o.codes[0] = o.a.submit.?(o.a, "outside", body, o.probe, null, 0, &o.first);
    o.codes[1] = o.a.submit.?(o.a, "outside", body, o.probe, null, 0, &second);
}

fn anotherThreadSubmitsUpToTheCapacityBetweenDrains(a: *c.ke_async) !void {
    var p: Probe = .{};
    var o: Outside = .{ .a = a, .probe = &p };
    const t = try std.Thread.spawn(.{}, submitTwiceFromOutside, .{&o});
    t.join();
    try testing.expectEqual(ok, o.codes[0]);
    try testing.expectEqual(abi_result.c.KE_RESULT_OUT_OF_MEMORY, o.codes[1]);
    try testing.expectEqual(ok, finish(o.first.?));
    try testing.expectEqual(@as(u32, 1), p.ran.load(.acquire));
}

fn aCompletionReleasedBeforeItFinishesStillRuns(a: *c.ke_async) !void {
    var foreign: Foreign = undefined;
    foreign.init();
    var p: Probe = .{};
    const early = try submit(a, body, &p, &.{&foreign.api});
    const after = try submit(a, body, &p, &.{early});
    early.release.?(early);
    foreign.complete(ok);
    try testing.expectEqual(ok, finish(after));
    a.drain.?(a);
    try testing.expectEqual(@as(u32, 2), p.ran.load(.acquire));
}

fn invalidArgumentsAreRefused(a: *c.ke_async) !void {
    const invalid = abi_result.c.KE_RESULT_INVALID_ARGUMENT;
    var out: ?*Completion = null;
    var p: Probe = .{};
    try testing.expectEqual(invalid, a.submit.?(null, "", body, &p, null, 0, &out));
    try testing.expectEqual(invalid, a.submit.?(a, "", null, &p, null, 0, &out));
    try testing.expectEqual(invalid, a.submit.?(a, "", body, &p, null, 0, null));
    const deps = [_]?*Completion{null};
    try testing.expectEqual(invalid, a.submit.?(a, "", body, &p, &deps, 1, &out));
    try testing.expect(out == null);
    var foreign: Foreign = undefined;
    foreign.init();
    try testing.expectEqual(invalid, a.cancel.?(a, &foreign.api));
    try testing.expectEqual(invalid, a.cancel.?(a, null));
}

pub const Case = struct { name: []const u8, run: *const fn (*c.ke_async) anyerror!void };

/// Every behaviour, by the sentence that states it.
pub const cases = [_]Case{
    .{ .name = "an operation's completion carries what the operation returned", .run = anOperationCarriesWhatItReturned },
    .{ .name = "an operation sees what each dependency of any origin finished with", .run = anOperationSeesWhatItsDependenciesFinishedWith },
    .{ .name = "an operation cancelled before it starts finishes cancelled without running", .run = anOperationCancelledBeforeItStartsFinishesCancelledWithoutRunning },
    .{ .name = "a running operation sees the cancellation", .run = aRunningOperationSeesTheCancellation },
    .{ .name = "another thread submits up to the capacity between drains", .run = anotherThreadSubmitsUpToTheCapacityBetweenDrains },
    .{ .name = "a completion released before it finishes still runs and frees", .run = aCompletionReleasedBeforeItFinishesStillRuns },
    .{ .name = "invalid arguments are refused and leave no completion", .run = invalidArgumentsAreRefused },
};

/// Runs every case on a system of its own, naming the case that failed.
pub fn check(create: Create) !void {
    for (cases) |case| {
        const h = try create();
        defer h.destroy.?(h.ref);
        case.run(h.ref.?) catch |err| {
            std.debug.print("async contract case failed: {s}\n", .{case.name});
            return err;
        };
    }
}

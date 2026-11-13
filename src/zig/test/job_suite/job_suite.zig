//! The behaviour every `ke_job_system` promises, run by the tests of each implementation against a
//! system it creates.

const std = @import("std");
const abi_job = @import("abi_job");
const abi_completion = @import("abi_completion");
const abi_result = @import("abi_result");

const c = abi_job.c;
const Completion = abi_completion.c.ke_completion;
const Result = abi_result.c.ke_result;
const ok = abi_result.c.KE_OK;
const not_found = abi_result.c.KE_RESULT_NOT_FOUND;
const testing = std.testing;

pub const Create = *const fn () anyerror!c.ke_job_system_handle;

/// A completion of another origin that the test finishes by hand.
pub const Foreign = struct {
    api: Completion,
    done: std.atomic.Value(bool) = .init(false),
    result: Result = ok,

    pub fn init(self: *Foreign) void {
        self.* = .{ .api = .{ .handle = self, .poll = poll, .wait = wait, .release = release } };
    }

    pub fn complete(self: *Foreign, result: Result) void {
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

fn returnCode(data: ?*anyopaque, _: ?*const c.ke_job_ctx) callconv(.c) Result {
    return @as(*const Result, @ptrCast(@alignCast(data.?))).*;
}

fn increment(data: ?*anyopaque, _: ?*const c.ke_job_ctx) callconv(.c) Result {
    _ = @as(*std.atomic.Value(u32), @ptrCast(@alignCast(data.?))).fetchAdd(1, .acq_rel);
    return ok;
}

const Seen = struct { results: [4]Result = .{ ok, ok, ok, ok }, count: u32 = 0 };

fn recordDeps(data: ?*anyopaque, ctx: ?*const c.ke_job_ctx) callconv(.c) Result {
    const seen: *Seen = @ptrCast(@alignCast(data.?));
    seen.count = ctx.?.dep_count;
    for (0..ctx.?.dep_count) |i| seen.results[i] = ctx.?.dep_results.?[i];
    return ok;
}

const Chain = struct { next: std.atomic.Value(u32) = .init(0), out_of_order: std.atomic.Value(bool) = .init(false) };
const Step = struct { chain: *Chain, index: u32 };

fn step(data: ?*anyopaque, _: ?*const c.ke_job_ctx) callconv(.c) Result {
    const s: *Step = @ptrCast(@alignCast(data.?));
    if (s.chain.next.fetchAdd(1, .acq_rel) != s.index) s.chain.out_of_order.store(true, .release);
    return ok;
}

const Cover = struct { hits: [1000]std.atomic.Value(u32), slots: u32, bad_index: std.atomic.Value(bool) = .init(false), fail_at: u32 = std.math.maxInt(u32) };

fn cover(data: ?*anyopaque, start: u32, end: u32, worker: u32) callconv(.c) Result {
    const cv: *Cover = @ptrCast(@alignCast(data.?));
    if (worker >= cv.slots) cv.bad_index.store(true, .release);
    var failed = false;
    for (start..end) |i| {
        _ = cv.hits[i].fetchAdd(1, .acq_rel);
        if (i == cv.fail_at) failed = true;
    }
    return if (failed) not_found else ok;
}

const Nested = struct { js: *c.ke_job_system, ran: std.atomic.Value(u32) = .init(0), result: Result = ok };

fn dispatchAndWaitInside(data: ?*anyopaque, _: ?*const c.ke_job_ctx) callconv(.c) Result {
    const n: *Nested = @ptrCast(@alignCast(data.?));
    var inner: ?*Completion = null;
    const r = n.js.dispatch.?(n.js, "inner", increment, &n.ran, null, 0, &inner);
    if (r != ok) return r;
    n.result = inner.?.wait.?(inner.?);
    inner.?.release.?(inner.?);
    return ok;
}

fn dispatchOne(js: *c.ke_job_system, label: [*:0]const u8, f: c.ke_job_fn, data: ?*anyopaque, deps: []const ?*Completion) !*Completion {
    var out: ?*Completion = null;
    try expectOk(js.dispatch.?(js, label, f, data, deps.ptr, @intCast(deps.len), &out));
    return out.?;
}

fn finish(done: *Completion) !Result {
    const r = done.wait.?(done);
    done.release.?(done);
    return r;
}

fn expectOk(r: Result) !void {
    try testing.expectEqual(ok, r);
}

fn aJobCarriesWhatItReturned(js: *c.ke_job_system) !void {
    var code: Result = not_found;
    try testing.expectEqual(not_found, try finish(try dispatchOne(js, "fails", returnCode, &code, &.{})));
    code = ok;
    try testing.expectEqual(ok, try finish(try dispatchOne(js, "succeeds", returnCode, &code, &.{})));
}

fn aJobSeesTheResultsOfItsDependenciesInOrder(js: *c.ke_job_system) !void {
    var failing: Result = not_found;
    var passing: Result = ok;
    const a = try dispatchOne(js, "a", returnCode, &failing, &.{});
    const b = try dispatchOne(js, "b", returnCode, &passing, &.{});
    var seen: Seen = .{};
    try expectOk(try finish(try dispatchOne(js, null_label, recordDeps, &seen, &.{ a, b })));
    try testing.expectEqual(@as(u32, 2), seen.count);
    try testing.expectEqual(not_found, seen.results[0]);
    try testing.expectEqual(ok, seen.results[1]);
    a.release.?(a);
    b.release.?(b);
}

const null_label: [*:0]const u8 = "";

fn aChainRunsInTheOrderItsDependenciesState(js: *c.ke_job_system) !void {
    var chain: Chain = .{};
    var steps: [64]Step = undefined;
    var done: [64]*Completion = undefined;
    for (&steps, 0..) |*s, i| {
        s.* = .{ .chain = &chain, .index = @intCast(i) };
        const deps: []const ?*Completion = if (i == 0) &.{} else &.{done[i - 1]};
        done[i] = try dispatchOne(js, "step", step, s, deps);
    }
    try expectOk(done[63].wait.?(done[63]));
    for (done) |d| d.release.?(d);
    try testing.expect(!chain.out_of_order.load(.acquire));
    try testing.expectEqual(@as(u32, 64), chain.next.load(.acquire));
}

fn parallelForCoversEveryItemOnce(js: *c.ke_job_system) !void {
    var cv: Cover = .{ .hits = undefined, .slots = js.worker_slots.?(js) };
    for (&cv.hits) |*h| h.* = .init(0);
    try testing.expect(cv.slots >= 1);
    var out: ?*Completion = null;
    try expectOk(js.parallel_for.?(js, "cover", cover, &cv, 1000, 7, null, 0, &out));
    try expectOk(try finish(out.?));
    for (&cv.hits) |*h| try testing.expectEqual(@as(u32, 1), h.load(.acquire));
    try testing.expect(!cv.bad_index.load(.acquire));
}

fn parallelForCarriesAFailureOfARange(js: *c.ke_job_system) !void {
    var cv: Cover = .{ .hits = undefined, .slots = js.worker_slots.?(js), .fail_at = 500 };
    for (&cv.hits) |*h| h.* = .init(0);
    var out: ?*Completion = null;
    try expectOk(js.parallel_for.?(js, "cover", cover, &cv, 1000, 0, null, 0, &out));
    try testing.expectEqual(not_found, try finish(out.?));
}

fn parallelForOverNoItemsFinishes(js: *c.ke_job_system) !void {
    var cv: Cover = .{ .hits = undefined, .slots = 1 };
    var out: ?*Completion = null;
    try expectOk(js.parallel_for.?(js, "none", cover, &cv, 0, 0, null, 0, &out));
    try expectOk(try finish(out.?));
}

fn aJobWaitsOnACompletionOfAnotherOrigin(js: *c.ke_job_system) !void {
    var foreign: Foreign = undefined;
    foreign.init();
    var seen: Seen = .{};
    const job = try dispatchOne(js, "after foreign", recordDeps, &seen, &.{&foreign.api});
    js.drain.?(js);
    var r: Result = ok;
    try testing.expect(!job.poll.?(job, &r));
    foreign.complete(not_found);
    try expectOk(try finish(job));
    try testing.expectEqual(not_found, seen.results[0]);
}

fn aJobDispatchesAndWaitsOnAnotherFromInside(js: *c.ke_job_system) !void {
    var n: Nested = .{ .js = js };
    try expectOk(try finish(try dispatchOne(js, "outer", dispatchAndWaitInside, &n, &.{})));
    try expectOk(n.result);
    try testing.expectEqual(@as(u32, 1), n.ran.load(.acquire));
}

fn aCompletionReleasedBeforeItFinishesIsStillRun(js: *c.ke_job_system) !void {
    var ran: std.atomic.Value(u32) = .init(0);
    var foreign: Foreign = undefined;
    foreign.init();
    const first = try dispatchOne(js, "released early", increment, &ran, &.{&foreign.api});
    const after = try dispatchOne(js, "after", increment, &ran, &.{first});
    foreign.complete(ok);
    try expectOk(try finish(after));
    first.release.?(first);
    js.drain.?(js);
    try testing.expectEqual(@as(u32, 2), ran.load(.acquire));
}

const Outside = struct { js: *c.ke_job_system, code: Result = ok };

fn dispatchFromOutside(o: *Outside) void {
    var ran: std.atomic.Value(u32) = .init(0);
    var out: ?*Completion = null;
    o.code = o.js.dispatch.?(o.js, "outside", increment, &ran, null, 0, &out);
}

fn aThreadOutsideTheSystemCannotDispatch(js: *c.ke_job_system) !void {
    var o: Outside = .{ .js = js };
    const t = try std.Thread.spawn(.{}, dispatchFromOutside, .{&o});
    t.join();
    try testing.expectEqual(abi_result.c.KE_RESULT_NOT_SUPPORTED, o.code);
}

fn invalidArgumentsAreRefused(js: *c.ke_job_system) !void {
    var out: ?*Completion = null;
    const invalid = abi_result.c.KE_RESULT_INVALID_ARGUMENT;
    try testing.expectEqual(invalid, js.dispatch.?(null, null_label, increment, null, null, 0, &out));
    try testing.expectEqual(invalid, js.dispatch.?(js, null_label, null, null, null, 0, &out));
    try testing.expectEqual(invalid, js.dispatch.?(js, null_label, increment, null, null, 0, null));
    const deps = [_]?*Completion{null};
    try testing.expectEqual(invalid, js.dispatch.?(js, null_label, increment, null, &deps, 1, &out));
    try testing.expectEqual(invalid, js.dispatch.?(js, null_label, increment, null, null, 1, &out));
    try testing.expectEqual(invalid, js.parallel_for.?(js, null_label, null, null, 1, 0, null, 0, &out));
    try testing.expect(out == null);
}

pub const Case = struct { name: []const u8, run: *const fn (*c.ke_job_system) anyerror!void };

/// Every behaviour, by the sentence that states it.
pub const cases = [_]Case{
    .{ .name = "a job's completion carries what the job returned", .run = aJobCarriesWhatItReturned },
    .{ .name = "a job sees what each dependency finished with, in the order given, failures included", .run = aJobSeesTheResultsOfItsDependenciesInOrder },
    .{ .name = "a chain of jobs runs in the order its dependencies state", .run = aChainRunsInTheOrderItsDependenciesState },
    .{ .name = "parallel_for covers every item exactly once with worker indices below worker_slots", .run = parallelForCoversEveryItemOnce },
    .{ .name = "parallel_for carries the failure of a range", .run = parallelForCarriesAFailureOfARange },
    .{ .name = "parallel_for over no items finishes", .run = parallelForOverNoItemsFinishes },
    .{ .name = "a job waits on a completion of another origin and sees its result", .run = aJobWaitsOnACompletionOfAnotherOrigin },
    .{ .name = "a job dispatches another and waits on it from inside", .run = aJobDispatchesAndWaitsOnAnotherFromInside },
    .{ .name = "a completion released before it finishes still runs and frees", .run = aCompletionReleasedBeforeItFinishesIsStillRun },
    .{ .name = "a thread outside the system cannot dispatch", .run = aThreadOutsideTheSystemCannotDispatch },
    .{ .name = "invalid arguments are refused and leave no completion", .run = invalidArgumentsAreRefused },
};

/// Runs every case on a system of its own, naming the case that failed.
pub fn check(create: Create) !void {
    for (cases) |case| {
        const h = try create();
        defer h.destroy.?(h.ref);
        case.run(h.ref.?) catch |err| {
            std.debug.print("job contract case failed: {s}\n", .{case.name});
            return err;
        };
    }
}

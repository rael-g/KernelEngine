//! The `ke_job_system` contract on enkiTS: each job a task set started once its dependencies
//! finished, ranges split by enkiTS, and work waiting on other origins started by the drain.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_job_system_enki").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const c = @import("c");
const abi_completion = @import("abi_completion");
const abi_job = @import("abi_job");
const abi_result = @import("abi_result");
const completion_graph = @import("completion_graph");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.job_system_enki);

const j = abi_job.c;
const Completion = abi_completion.c.ke_completion;
const Result = abi_result.c.ke_result;

/// What a node of this system runs: one body, or a body per range of `item_count` items, where
/// `remaining` counts the items not yet done and `failure` keeps the first failure of a range.
/// `set` is the enkiTS task set once the node started.
const JobPayload = struct {
    body: j.ke_job_fn = null,
    range: j.ke_job_range_fn = null,
    data: ?*anyopaque = null,
    item_count: u32 = 0,
    min_range: u32 = 0,
    remaining: std.atomic.Value(u32) = .init(0),
    failure: std.atomic.Value(Result) = .init(abi_result.c.KE_OK),
    set: std.atomic.Value(?*c.enkiTaskSet) = .init(null),
    label: []u8 = &.{},
};

const Graph = completion_graph.Graph(State);
const Node = Graph.Node;

/// The state behind the handle, whose `api.handle` points back at it. `host` is the thread that
/// created the system; `zero_workers` makes the drain run every queued job on it.
const State = struct {
    pub const Payload = JobPayload;

    api: j.ke_job_system,
    ets: *c.enkiTaskScheduler,
    host: std.Thread.Id,
    zero_workers: bool,
    graph: Graph,

    pub fn start(self: *State, node: *Node) void {
        const set = c.enkiCreateTaskSet(self.ets, execute) orelse {
            log.warn("a job could not be started: enkiTS gave no task set", .{});
            self.graph.finish(node, R.code(error.OutOfMemory));
            return;
        };
        node.payload.set.store(set, .release);
        if (node.payload.range != null) {
            if (node.payload.item_count == 0) {
                self.graph.finish(node, abi_result.c.KE_OK);
                return;
            }
            node.payload.remaining.store(node.payload.item_count, .release);
            c.enkiAddTaskSetMinRange(self.ets, set, node, node.payload.item_count, @max(node.payload.min_range, 1));
        } else c.enkiAddTaskSetArgs(self.ets, set, node, 1);
    }

    pub fn wait(self: *State, node: *Node) Result {
        const on_host = self.isHost();
        if (!on_host and current != self) {
            log.warn("wait refused: the calling thread is neither the creating thread nor a job of this system", .{});
            return R.code(error.NotSupported);
        }
        while (!node.finished.load(.acquire)) {
            if (on_host) self.graph.drain();
            if (node.payload.set.load(.acquire)) |set| c.enkiWaitForTaskSet(self.ets, set) else {
                c.enkiWaitForTaskSet(self.ets, null);
                std.Thread.yield() catch {};
            }
        }
        return node.result;
    }

    pub fn canFree(self: *State, node: *Node) bool {
        const set = node.payload.set.load(.acquire) orelse return true;
        return c.enkiIsTaskSetComplete(self.ets, set) != 0;
    }

    pub fn deinitPayload(self: *State, node: *Node) void {
        if (node.payload.set.load(.acquire)) |set| c.enkiDeleteTaskSet(self.ets, set);
        heap.gpa.free(node.payload.label);
    }

    fn isHost(self: *State) bool {
        return std.Thread.getCurrentId() == self.host;
    }
};

threadlocal var current: ?*State = null;

fn stateOf(self: *j.ke_job_system) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// The enkiTS entry of every task set: runs the node's body, or one range of it, as a job of the
/// system, and finishes the node when its last item is done.
fn execute(start: u32, end: u32, threadnum: u32, args: ?*anyopaque) callconv(.c) void {
    const node: *Node = @ptrCast(@alignCast(args.?));
    const self = node.graph.backend;
    const previous = current;
    current = self;
    defer current = previous;
    const p = &node.payload;
    if (p.body) |body| {
        const ctx: j.ke_job_ctx = .{ .dep_results = node.dep_results.ptr, .dep_count = @intCast(node.dep_results.len) };
        self.graph.finish(node, body(p.data, &ctx));
        return;
    }
    const r = p.range.?(p.data, start, end, threadnum);
    if (r != abi_result.c.KE_OK) _ = p.failure.cmpxchgStrong(abi_result.c.KE_OK, r, .acq_rel, .acquire);
    const count = end - start;
    if (p.remaining.fetchSub(count, .acq_rel) == count) self.graph.finish(node, p.failure.load(.acquire));
}

fn admit(self: *State, deps: ?[*]const ?*Completion, dep_count: u32) R.Error![]const ?*Completion {
    const list: []const ?*Completion = if (dep_count == 0) &.{} else (deps orelse return error.InvalidArgument)[0..dep_count];
    for (list) |d| if (d == null) return error.InvalidArgument;
    if (!self.isHost() and current != self) {
        log.warn("dispatch refused: the calling thread is neither the creating thread nor a job of this system", .{});
        return error.NotSupported;
    }
    return list;
}

fn enqueue(self: *State, label: ?[*:0]const u8, deps: []const ?*Completion, payload: JobPayload, out: *?*Completion) R.Error!void {
    var p = payload;
    p.label = heap.gpa.dupe(u8, if (label) |l| std.mem.span(l) else "") catch return error.OutOfMemory;
    errdefer heap.gpa.free(p.label);
    const node = self.graph.alloc(deps, p) catch return error.OutOfMemory;
    out.* = &node.api;
    self.graph.link(node);
}

/// Slot `dispatch`.
fn dispatch(self_in: ?*j.ke_job_system, label: ?[*:0]const u8, body: j.ke_job_fn, data: ?*anyopaque, deps: ?[*]const ?*Completion, dep_count: u32, out_completion: ?*?*Completion) callconv(.c) Result {
    const out = out_completion orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (body == null) return R.code(error.InvalidArgument);
    const list = admit(self, deps, dep_count) catch |err| return R.code(err);
    enqueue(self, label, list, .{ .body = body, .data = data }, out) catch |err| return R.code(err);
    return R.ok;
}

/// Slot `parallel_for`.
fn parallelFor(self_in: ?*j.ke_job_system, label: ?[*:0]const u8, range: j.ke_job_range_fn, data: ?*anyopaque, item_count: u32, min_range: u32, deps: ?[*]const ?*Completion, dep_count: u32, out_completion: ?*?*Completion) callconv(.c) Result {
    const out = out_completion orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (range == null) return R.code(error.InvalidArgument);
    const list = admit(self, deps, dep_count) catch |err| return R.code(err);
    enqueue(self, label, list, .{ .range = range, .data = data, .item_count = item_count, .min_range = min_range }, out) catch |err| return R.code(err);
    return R.ok;
}

/// Slot `worker_slots`: every enkiTS thread, the creating one included.
fn workerSlots(self_in: ?*j.ke_job_system) callconv(.c) u32 {
    const self = stateOf(self_in orelse return 0);
    return c.enkiGetNumTaskThreads(self.ets);
}

/// Slot `drain`.
fn drain(self_in: ?*j.ke_job_system) callconv(.c) void {
    const self = stateOf(self_in orelse return);
    if (!self.isHost()) return;
    self.graph.drain();
    if (self.zero_workers) c.enkiWaitForAll(self.ets);
}

/// The handle's `destroy`: runs what enkiTS holds, frees the released jobs and the scheduler.
fn destroy(self_in: ?*j.ke_job_system) callconv(.c) void {
    const self = stateOf(self_in orelse return);
    self.graph.drain();
    c.enkiWaitForAll(self.ets);
    self.graph.deinit();
    c.enkiDeleteTaskScheduler(self.ets);
    heap.gpa.destroy(self);
}

export fn ke_job_system_enki_create(config_in: ?*const j.ke_job_system_config, out_job_system: ?*j.ke_job_system_handle) callconv(.c) Result {
    const out = out_job_system orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(j.ke_job_system_handle);
    out.* = create(config_in) catch |err| {
        log.warn("creating the job system failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(config_in: ?*const j.ke_job_system_config) R.Error!j.ke_job_system_handle {
    const config = config_in orelse return error.InvalidArgument;
    const self = heap.gpa.create(State) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(self);
    const ets = c.enkiNewTaskScheduler() orelse return error.General;
    const workers: u32 = if (config.worker_count == j.KE_JOB_SYSTEM_WORKERS_PER_HARDWARE_THREAD) @intCast(@max(std.Thread.getCpuCount() catch 1, 1) - 1) else config.worker_count;
    c.enkiInitTaskSchedulerNumThreads(ets, workers + 1);
    self.* = .{
        .api = .{ .handle = self, .dispatch = dispatch, .parallel_for = parallelFor, .worker_slots = workerSlots, .drain = drain },
        .ets = ets,
        .host = std.Thread.getCurrentId(),
        .zero_workers = workers == 0,
        .graph = undefined,
    };
    self.graph = Graph.init(self, heap.gpa);
    return .{ .ref = &self.api, .destroy = destroy };
}

const testing = std.testing;

fn createdWith(workers: u32) !j.ke_job_system_handle {
    var h: j.ke_job_system_handle = undefined;
    try R.check(ke_job_system_enki_create(&.{ .worker_count = workers }, &h));
    return h;
}

fn createdWithWorkers() anyerror!j.ke_job_system_handle {
    return createdWith(3);
}

fn createdWithoutWorkers() anyerror!j.ke_job_system_handle {
    return createdWith(0);
}

test "a job system with workers keeps the job system contract" {
    try @import("job_suite").check(createdWithWorkers);
}

test "a job system without workers keeps the job system contract" {
    try @import("job_suite").check(createdWithoutWorkers);
}

test "one worker per hardware thread besides the creating one gives a slot per hardware thread" {
    const h = try createdWith(j.KE_JOB_SYSTEM_WORKERS_PER_HARDWARE_THREAD);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(@as(u32, @intCast(@max(std.Thread.getCpuCount() catch 1, 1))), h.ref.?.worker_slots.?(h.ref));
}

test "worker slots count the workers and the creating thread" {
    const h = try createdWith(3);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(@as(u32, 4), h.ref.?.worker_slots.?(h.ref));
}

test "a null config or handle is refused as an invalid argument" {
    var h: j.ke_job_system_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_job_system_enki_create(null, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_job_system_enki_create(&.{ .worker_count = 0 }, null)));
}

test "creating and destroying job systems leaves no block allocated" {
    const h = try createdWith(2);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

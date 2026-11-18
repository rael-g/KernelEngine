//! The `ke_job_system` contract with no thread of its own: every job runs on the creating thread,
//! in the order it became ready, when that thread waits or drains.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_job_system_inline").logFn };

const abi_completion = @import("abi_completion");
const abi_job = @import("abi_job");
const abi_result = @import("abi_result");
const completion_graph = @import("completion_graph");
const heap = @import("heap");

const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const R = @import("result").Result(.{});
const log = std.log.scoped(.job_system_inline);

const j = abi_job.c;
const Completion = abi_completion.c.ke_completion;
const Result = abi_result.c.ke_result;

/// What a node runs: one body, or one range over every item; `next_ready` threads the queue of
/// nodes whose dependencies all finished.
const JobPayload = struct {
    body: j.ke_job_fn = null,
    range: j.ke_job_range_fn = null,
    data: ?*anyopaque = null,
    item_count: u32 = 0,
    label: []u8 = &.{},
    next_ready: ?*Graph.Node = null,
};

const Graph = completion_graph.Graph(State);
const Node = Graph.Node;

/// The state behind the handle, whose `api.handle` points back at it. `ready` and `last` are the
/// queue of nodes to run, touched only by the creating thread `host`.
const State = struct {
    pub const Payload = JobPayload;

    api: j.ke_job_system,
    host: std.Thread.Id,
    graph: Graph,
    ready: ?*Node = null,
    last: ?*Node = null,

    pub fn start(self: *State, node: *Node) void {
        node.payload.next_ready = null;
        if (self.last) |l| l.payload.next_ready = node else self.ready = node;
        self.last = node;
    }

    pub fn wait(self: *State, node: *Node) Result {
        if (!self.isHost()) {
            log.warn("wait refused: the calling thread is not the creating thread", .{});
            return R.code(error.NotSupported);
        }
        while (!node.finished.load(.acquire)) {
            if (self.runOne()) continue;
            self.graph.drain();
            if (!self.runOne() and !node.finished.load(.acquire)) std.Thread.yield() catch {};
        }
        return node.result;
    }

    pub fn canFree(_: *State, _: *Node) bool {
        return true;
    }

    pub fn deinitPayload(_: *State, node: *Node) void {
        heap.gpa.free(node.payload.label);
    }

    fn isHost(self: *State) bool {
        return std.Thread.getCurrentId() == self.host;
    }

    fn runOne(self: *State) bool {
        const node = self.ready orelse return false;
        self.ready = node.payload.next_ready;
        if (self.ready == null) self.last = null;
        const p = &node.payload;
        const result = if (p.body) |body| blk: {
            const ctx: j.ke_job_ctx = .{ .dep_results = node.dep_results.ptr, .dep_count = @intCast(node.dep_results.len) };
            break :blk body(p.data, &ctx);
        } else if (p.item_count == 0) abi_result.c.KE_OK else p.range.?(p.data, 0, p.item_count, 0);
        self.graph.finish(node, result);
        return true;
    }
};

fn stateOf(self: *j.ke_job_system) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn enqueue(self: *State, label: ?[*:0]const u8, deps: ?[*]const ?*Completion, dep_count: u32, payload: JobPayload, out: *?*Completion) R.Error!void {
    const list: []const ?*Completion = if (dep_count == 0) &.{} else (deps orelse return error.InvalidArgument)[0..dep_count];
    for (list) |d| if (d == null) return error.InvalidArgument;
    if (!self.isHost()) {
        log.warn("dispatch refused: the calling thread is not the creating thread", .{});
        return error.NotSupported;
    }
    var p = payload;
    p.label = heap.gpa.dupe(u8, if (label) |l| std.mem.span(l) else "") catch return error.OutOfMemory;
    errdefer heap.gpa.free(p.label);
    const node = self.graph.alloc(list, p) catch return error.OutOfMemory;
    out.* = &node.api;
    self.graph.link(node);
}

/// Slot `dispatch`.
fn dispatch(self_in: ?*j.ke_job_system, label: ?[*:0]const u8, body: j.ke_job_fn, data: ?*anyopaque, deps: ?[*]const ?*Completion, dep_count: u32, out_completion: ?*?*Completion) callconv(.c) Result {
    const out = out_completion orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (body == null) return R.code(error.InvalidArgument);
    enqueue(self, label, deps, dep_count, .{ .body = body, .data = data }, out) catch |err| return R.code(err);
    return R.ok;
}

/// Slot `parallel_for`: one range over every item.
fn parallelFor(self_in: ?*j.ke_job_system, label: ?[*:0]const u8, range: j.ke_job_range_fn, data: ?*anyopaque, item_count: u32, min_range: u32, deps: ?[*]const ?*Completion, dep_count: u32, out_completion: ?*?*Completion) callconv(.c) Result {
    _ = min_range;
    const out = out_completion orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (range == null) return R.code(error.InvalidArgument);
    enqueue(self, label, deps, dep_count, .{ .range = range, .data = data, .item_count = item_count }, out) catch |err| return R.code(err);
    return R.ok;
}

/// Slot `worker_slots`: the creating thread alone.
fn workerSlots(self_in: ?*j.ke_job_system) callconv(.c) u32 {
    _ = self_in orelse return 0;
    return 1;
}

/// Slot `drain`: polls the other origins and runs every job that becomes ready.
fn drain(self_in: ?*j.ke_job_system) callconv(.c) void {
    const self = stateOf(self_in orelse return);
    if (!self.isHost()) return;
    self.graph.drain();
    while (self.runOne()) {}
}

/// The handle's `destroy`: runs what is ready and frees the released jobs.
fn destroy(self_in: ?*j.ke_job_system) callconv(.c) void {
    const self = stateOf(self_in orelse return);
    drain(self_in);
    self.graph.deinit();
    heap.gpa.destroy(self);
}

/// The job system's settings: the contract's worker count, which only zero satisfies.
const Settings = struct {
    worker_count: u32 = 0,

    pub const ranges = .{ .worker_count = .{ 0, 0 } };
};

export fn ke_job_system_inline_create(settings: ?*abi_settings.c.ke_settings, out_job_system: ?*j.ke_job_system_handle) callconv(.c) Result {
    const out = out_job_system orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(j.ke_job_system_handle);
    out.* = create(settings) catch |err| {
        log.warn("creating the job system failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(settings: ?*abi_settings.c.ke_settings) R.Error!j.ke_job_system_handle {
    _ = try settings_schema.read(Settings, settings orelse return error.InvalidArgument);
    const self = heap.gpa.create(State) catch return error.OutOfMemory;
    self.* = .{
        .api = .{ .handle = self, .dispatch = dispatch, .parallel_for = parallelFor, .worker_slots = workerSlots, .drain = drain },
        .host = std.Thread.getCurrentId(),
        .graph = undefined,
    };
    self.graph = Graph.init(self, heap.gpa);
    return .{ .ref = &self.api, .destroy = destroy };
}

const testing = std.testing;

fn created() anyerror!j.ke_job_system_handle {
    var h: j.ke_job_system_handle = undefined;
    var none = settings_schema.Fixed.init(&.{});
    try R.check(ke_job_system_inline_create(&none.api, &h));
    return h;
}

test "an inline job system keeps the job system contract" {
    try @import("job_suite").check(created);
}

test "a job runs only when the creating thread waits or drains" {
    const h = try created();
    defer h.destroy.?(h.ref);
    var ran: std.atomic.Value(u32) = .init(0);
    var out: ?*Completion = null;
    try R.check(h.ref.?.dispatch.?(h.ref, "later", countRun, &ran, null, 0, &out));
    try testing.expectEqual(@as(u32, 0), ran.load(.acquire));
    h.ref.?.drain.?(h.ref);
    try testing.expectEqual(@as(u32, 1), ran.load(.acquire));
    out.?.release.?(out.?);
}

fn countRun(data: ?*anyopaque, _: ?*const j.ke_job_ctx) callconv(.c) Result {
    _ = @as(*std.atomic.Value(u32), @ptrCast(@alignCast(data.?))).fetchAdd(1, .acq_rel);
    return R.ok;
}

test "a worker count other than zero is refused" {
    var h: j.ke_job_system_handle = undefined;
    var one = settings_schema.Fixed.init(&.{.{ .key = "worker_count", .value = .{ .int = 1 } }});
    try testing.expectError(error.InvalidArgument, R.check(ke_job_system_inline_create(&one.api, &h)));
}

test "creating and destroying job systems leaves no block allocated" {
    const h = try created();
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

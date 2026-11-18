//! The `ke_async` contract with no thread of its own: every operation runs on the creating thread,
//! in the order it became ready, when that thread waits or drains; submissions from other threads
//! wait in a ring for it.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_async_inline").logFn };

const abi_async = @import("abi_async");
const abi_completion = @import("abi_completion");
const abi_result = @import("abi_result");
const completion_graph = @import("completion_graph");
const heap = @import("heap");

const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const R = @import("result").Result(.{});
const log = std.log.scoped(.async_inline);

const a = abi_async.c;
const Completion = abi_completion.c.ke_completion;
const Result = abi_result.c.ke_result;

/// What a node runs, the context its body sees, whether it was cancelled, and the link of the
/// queue of ready nodes.
const OpPayload = struct {
    body: a.ke_async_fn = null,
    data: ?*anyopaque = null,
    ctx: a.ke_async_ctx = std.mem.zeroes(a.ke_async_ctx),
    cancelled: std.atomic.Value(bool) = .init(false),
    label: []u8 = &.{},
    next_ready: ?*Graph.Node = null,
};

const Graph = completion_graph.Graph(State);
const Node = Graph.Node;

/// The state behind the handle, whose `api.handle` points back at it. `ready` and `last` are the
/// queue of nodes to run and `outside` the nodes other threads submitted; the creating thread
/// `host` alone runs and links them.
const State = struct {
    pub const Payload = OpPayload;

    api: a.ke_async,
    host: std.Thread.Id,
    graph: Graph,
    outside: completion_graph.Ring(*Node),
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
            self.takeOutside();
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

    fn takeOutside(self: *State) void {
        while (self.outside.pop()) |node| self.graph.link(node);
    }

    fn runOne(self: *State) bool {
        const node = self.ready orelse return false;
        self.ready = node.payload.next_ready;
        if (self.ready == null) self.last = null;
        const p = &node.payload;
        if (p.cancelled.load(.acquire)) {
            self.graph.finish(node, R.code(error.Cancelled));
            return true;
        }
        p.ctx = .{ .handle = node, .dep_results = node.dep_results.ptr, .dep_count = @intCast(node.dep_results.len), .cancelled = cancelled };
        self.graph.finish(node, p.body.?(p.data, &p.ctx));
        return true;
    }
};

fn stateOf(self: *a.ke_async) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// Slot `cancelled` of the context an operation sees.
fn cancelled(ctx_in: ?*a.ke_async_ctx) callconv(.c) bool {
    const node: *Node = @ptrCast(@alignCast((ctx_in orelse return false).handle));
    return node.payload.cancelled.load(.acquire);
}

fn enqueue(self: *State, label: ?[*:0]const u8, body: a.ke_async_fn, data: ?*anyopaque, deps: ?[*]const ?*Completion, dep_count: u32, out: *?*Completion) R.Error!void {
    const list: []const ?*Completion = if (dep_count == 0) &.{} else (deps orelse return error.InvalidArgument)[0..dep_count];
    for (list) |d| if (d == null) return error.InvalidArgument;
    const copy = heap.gpa.dupe(u8, if (label) |l| std.mem.span(l) else "") catch return error.OutOfMemory;
    const node = self.graph.alloc(list, .{ .body = body, .data = data, .label = copy }) catch {
        heap.gpa.free(copy);
        return error.OutOfMemory;
    };
    if (self.isHost()) {
        out.* = &node.api;
        self.graph.link(node);
        return;
    }
    if (!self.outside.push(node)) {
        log.warn("submit refused: the queue for other threads is full until the next drain", .{});
        self.graph.discard(node);
        return error.OutOfMemory;
    }
    out.* = &node.api;
}

/// Slot `submit`.
fn submit(self_in: ?*a.ke_async, label: ?[*:0]const u8, body: a.ke_async_fn, data: ?*anyopaque, deps: ?[*]const ?*Completion, dep_count: u32, out_completion: ?*?*Completion) callconv(.c) Result {
    const out = out_completion orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = stateOf(self_in orelse return R.code(error.InvalidArgument));
    if (body == null) return R.code(error.InvalidArgument);
    enqueue(self, label, body, data, deps, dep_count, out) catch |err| return R.code(err);
    return R.ok;
}

/// Slot `cancel`.
fn cancel(self_in: ?*a.ke_async, completion: ?*Completion) callconv(.c) Result {
    const self = stateOf(self_in orelse return R.code(error.InvalidArgument));
    const node = self.graph.own(completion orelse return R.code(error.InvalidArgument)) orelse return R.code(error.InvalidArgument);
    node.payload.cancelled.store(true, .release);
    return R.ok;
}

/// Slot `drain`: links what other threads submitted, polls the other origins and runs every
/// operation that becomes ready.
fn drain(self_in: ?*a.ke_async) callconv(.c) void {
    const self = stateOf(self_in orelse return);
    if (!self.isHost()) return;
    self.takeOutside();
    self.graph.drain();
    while (self.runOne()) {}
}

/// The handle's `destroy`: runs what is ready and frees the released operations.
fn destroy(self_in: ?*a.ke_async) callconv(.c) void {
    const self = stateOf(self_in orelse return);
    drain(self_in);
    self.graph.deinit();
    self.outside.deinit();
    heap.gpa.destroy(self);
}

/// The async system's settings, with this implementation's defaults.
const Settings = struct {
    worker_count: u32 = 0,
    submit_capacity: u32 = 1024,

    pub const ranges = .{ .worker_count = .{ 0, 0 }, .submit_capacity = .{ 1, std.math.maxInt(u32) } };
};

export fn ke_async_inline_create(settings: ?*abi_settings.c.ke_settings, out_async: ?*a.ke_async_handle) callconv(.c) Result {
    const out = out_async orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(a.ke_async_handle);
    out.* = create(settings) catch |err| {
        log.warn("creating the async system failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(settings: ?*abi_settings.c.ke_settings) R.Error!a.ke_async_handle {
    const config = try settings_schema.read(Settings, settings orelse return error.InvalidArgument);
    const self = heap.gpa.create(State) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(self);
    const outside = completion_graph.Ring(*Node).init(heap.gpa, config.submit_capacity) catch return error.OutOfMemory;
    self.* = .{
        .api = .{ .handle = self, .submit = submit, .cancel = cancel, .drain = drain },
        .host = std.Thread.getCurrentId(),
        .graph = undefined,
        .outside = outside,
    };
    self.graph = Graph.init(self, heap.gpa);
    return .{ .ref = &self.api, .destroy = destroy };
}

const testing = std.testing;

fn created() anyerror!a.ke_async_handle {
    var h: a.ke_async_handle = undefined;
    var one = settings_schema.Fixed.init(&.{.{ .key = "submit_capacity", .value = .{ .int = 1 } }});
    try R.check(ke_async_inline_create(&one.api, &h));
    return h;
}

test "an inline async system keeps the async contract" {
    try @import("async_suite").check(created);
}

test "a worker count other than zero or a submit_capacity of zero is refused" {
    var h: a.ke_async_handle = undefined;
    var worker = settings_schema.Fixed.init(&.{.{ .key = "worker_count", .value = .{ .int = 1 } }});
    try testing.expectError(error.InvalidArgument, R.check(ke_async_inline_create(&worker.api, &h)));
    var empty = settings_schema.Fixed.init(&.{.{ .key = "submit_capacity", .value = .{ .int = 0 } }});
    try testing.expectError(error.InvalidArgument, R.check(ke_async_inline_create(&empty.api, &h)));
}

test "creating and destroying async systems leaves no block allocated" {
    const h = try created();
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

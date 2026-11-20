//! The `ke_async` contract on enkiTS: each operation a task set on workers that may block, started
//! once its dependencies finished; submissions from other threads wait in a ring for the drain.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_async_enki").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const c = @import("c");
const abi_async = @import("abi_async");
const abi_completion = @import("abi_completion");
const abi_part = @import("abi_part");
const part = @import("part");
const abi_result = @import("abi_result");
const completion_graph = @import("completion_graph");
const heap = @import("heap");

const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const R = @import("result").Result(.{});
const log = std.log.scoped(.async_enki);

const a = abi_async.c;
const Completion = abi_completion.c.ke_completion;
const Result = abi_result.c.ke_result;

/// What a node runs, the context its body sees, whether it was cancelled, and its enkiTS task set
/// once started.
const OpPayload = struct {
    body: a.ke_async_fn = null,
    data: ?*anyopaque = null,
    ctx: a.ke_async_ctx = std.mem.zeroes(a.ke_async_ctx),
    cancelled: std.atomic.Value(bool) = .init(false),
    set: std.atomic.Value(?*c.enkiTaskSet) = .init(null),
    label: []u8 = &.{},
};

const Graph = completion_graph.Graph(State);
const Node = Graph.Node;

/// The state behind the handle, whose `api.handle` points back at it. `host` is the creating
/// thread; `outside` holds the nodes submitted from other threads until the host links them.
const State = struct {
    pub const Payload = OpPayload;

    api: a.ke_async,
    ets: *c.enkiTaskScheduler,
    host: std.Thread.Id,
    zero_workers: bool,
    graph: Graph,
    outside: completion_graph.Ring(*Node),

    pub fn start(self: *State, node: *Node) void {
        if (node.payload.cancelled.load(.acquire)) {
            self.graph.finish(node, R.code(error.Cancelled));
            return;
        }
        const set = c.enkiCreateTaskSet(self.ets, execute) orelse {
            log.warn("an operation could not be started: enkiTS gave no task set", .{});
            self.graph.finish(node, R.code(error.OutOfMemory));
            return;
        };
        node.payload.set.store(set, .release);
        c.enkiAddTaskSetArgs(self.ets, set, node, 1);
    }

    pub fn wait(self: *State, node: *Node) Result {
        if (!self.isHost()) {
            log.warn("wait refused: the calling thread is not the creating thread", .{});
            return R.code(error.NotSupported);
        }
        while (!node.finished.load(.acquire)) {
            self.takeOutside();
            self.graph.drain();
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

    fn takeOutside(self: *State) void {
        while (self.outside.pop()) |node| self.graph.link(node);
    }
};

threadlocal var current: ?*State = null;

fn stateOf(self: *a.ke_async) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// The enkiTS entry of every task set: runs the node's body as an operation of the system.
fn execute(_: u32, _: u32, _: u32, args: ?*anyopaque) callconv(.c) void {
    const node: *Node = @ptrCast(@alignCast(args.?));
    const self = node.graph.backend;
    const previous = current;
    current = self;
    defer current = previous;
    const p = &node.payload;
    p.ctx = .{ .handle = node, .dep_results = node.dep_results.ptr, .dep_count = @intCast(node.dep_results.len), .cancelled = cancelled };
    self.graph.finish(node, p.body.?(p.data, &p.ctx));
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
    if (self.isHost() or current == self) {
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

/// Slot `drain`.
fn drain(self_in: ?*a.ke_async) callconv(.c) void {
    const self = stateOf(self_in orelse return);
    if (!self.isHost()) return;
    self.takeOutside();
    self.graph.drain();
    if (self.zero_workers) c.enkiWaitForAll(self.ets);
}

/// The handle's `destroy`: runs what enkiTS holds, frees the released operations and the scheduler.
fn destroy(self_in: ?*a.ke_async) callconv(.c) void {
    const self = stateOf(self_in orelse return);
    self.takeOutside();
    self.graph.drain();
    c.enkiWaitForAll(self.ets);
    self.graph.deinit();
    self.outside.deinit();
    c.enkiDeleteTaskScheduler(self.ets);
    heap.gpa.destroy(self);
}

/// The async system's settings, with this implementation's defaults: an absent worker count is a
/// quarter of the hardware threads, at least one, so the frame keeps the cores.
const Settings = struct {
    worker_count: ?u32 = null,
    submit_capacity: u32 = 1024,

    pub const ranges = .{ .worker_count = .{ 0, std.math.maxInt(u32) }, .submit_capacity = .{ 1, std.math.maxInt(u32) } };
};

export fn ke_async_enki_create(settings: ?*abi_settings.c.ke_settings, out_async: ?*a.ke_async_handle) callconv(.c) Result {
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
    var outside = completion_graph.Ring(*Node).init(heap.gpa, config.submit_capacity) catch return error.OutOfMemory;
    errdefer outside.deinit();
    const ets = c.enkiNewTaskScheduler() orelse return error.General;
    const workers: u32 = config.worker_count orelse @intCast(@max(1, (std.Thread.getCpuCount() catch 1) / 4));
    c.enkiInitTaskSchedulerNumThreads(ets, workers + 1);
    self.* = .{
        .api = .{ .handle = self, .submit = submit, .cancel = cancel, .drain = drain },
        .ets = ets,
        .host = std.Thread.getCurrentId(),
        .zero_workers = workers == 0,
        .graph = undefined,
        .outside = outside,
    };
    self.graph = Graph.init(self, heap.gpa);
    return .{ .ref = &self.api, .destroy = destroy };
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(ke_async_enki_create, .{ .name = "async_enki", .slots = &.{}, .set_log = @ptrCast(&@import("log").Destination("ke_async_enki").setLogCallback) }),
};

/// The library's parts.
export fn ke_async_enki_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

const testing = std.testing;

fn createdWith(workers: u32) !a.ke_async_handle {
    var settings = settings_schema.Fixed.init(&.{ .{ .key = "worker_count", .value = .{ .int = workers } }, .{ .key = "submit_capacity", .value = .{ .int = 1 } } });
    var h: a.ke_async_handle = undefined;
    try R.check(ke_async_enki_create(&settings.api, &h));
    return h;
}

fn createdWithWorkers() anyerror!a.ke_async_handle {
    return createdWith(2);
}

fn createdWithoutWorkers() anyerror!a.ke_async_handle {
    return createdWith(0);
}

test "an async system with workers keeps the async contract" {
    try @import("async_suite").check(createdWithWorkers);
}

test "an async system without workers keeps the async contract" {
    try @import("async_suite").check(createdWithoutWorkers);
}

test "a null config, a null handle or a submit_capacity of zero is refused" {
    var h: a.ke_async_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_async_enki_create(null, &h)));
    var none = settings_schema.Fixed.init(&.{});
    try testing.expectError(error.InvalidArgument, R.check(ke_async_enki_create(&none.api, null)));
    var empty = settings_schema.Fixed.init(&.{.{ .key = "submit_capacity", .value = .{ .int = 0 } }});
    try testing.expectError(error.InvalidArgument, R.check(ke_async_enki_create(&empty.api, &h)));
}

test "the library's part is async_enki, built from its factory" {
    var count: usize = 0;
    const p = ke_async_enki_parts(&count).?;
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualStrings("async_enki", std.mem.span(p.name.?));
    try std.testing.expectEqual(@as(usize, 1), p.provides_count);
    try std.testing.expectEqual(@as(usize, 0), p.slot_count);
    try std.testing.expectEqual(@as(usize, 0), p.hook_count);
}

test "creating and destroying async systems leaves no block allocated" {
    const h = try createdWith(1);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

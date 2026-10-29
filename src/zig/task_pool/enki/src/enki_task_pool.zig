//! The `ke_task_pool` contract implemented on enkiTS, the one worker pool the engine's parallel
//! work goes through. It owns the tasks it dispatches until they are waited on.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_task_pool_enki").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const c = @import("c");
const abi_result = @import("abi_result");
const abi_task_pool = @import("abi_task_pool");
const abi_task_pool_enki_factory = @import("abi_task_pool_enki_factory");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.task_pool_enki);

/// One dispatched body and its outcome, allocated by `allocTask` and freed by `wait`, so it lives
/// from dispatch until the task is waited on. The worker writes `completed` and `result`; the
/// waiting thread reads `result` only after enkiTS reports the task finished.
const Task = struct {
    func: abi_task_pool.ke_task_func,
    data: ?*anyopaque,
    on_complete: abi_task_pool.ke_task_on_complete_func,
    on_complete_user_data: ?*anyopaque,
    completed: std.atomic.Value(bool),
    handle: ?*anyopaque,
    result: abi_result.ke_result,

    /// Runs on the worker that takes the task. `completed` is stored before the completion
    /// callback is called, so the callback can rely on `isCompleted` reporting true.
    fn run(self: *Task) void {
        if (self.func) |f| self.result = f(self.data);
        self.completed.store(true, .release);
        if (self.on_complete) |done| done(@ptrCast(self), self.on_complete_user_data, self.result);
    }
};

/// The allocation behind one handle. `api` is the vtable the handle's `ref` points at, and its
/// `handle` slot points back at this block. `ets` is created by the factory and deleted by
/// `destroy`.
const State = struct {
    api: abi_task_pool.ke_task_pool,
    ets: ?*c.enkiTaskScheduler,
};

fn stateOf(self: *abi_task_pool.ke_task_pool) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// The enkiTS task-set entry point. `dispatchOnComplete` adds each set with a size of one, so the
/// range and thread index enkiTS passes carry nothing and are ignored.
fn taskSetExecute(start: u32, end: u32, threadnum: u32, args: ?*anyopaque) callconv(.c) void {
    _ = start;
    _ = end;
    _ = threadnum;
    const task: *Task = @ptrCast(@alignCast(args orelse return));
    task.run();
}

/// Allocates a `Task` with `completed` false, `result` OK and no enkiTS object yet. The caller
/// fills `handle` once the enkiTS object exists. Returns null, having allocated
/// nothing, when the allocation fails.
fn allocTask(
    func: abi_task_pool.ke_task_func,
    data: ?*anyopaque,
    on_complete: abi_task_pool.ke_task_on_complete_func,
    user_data: ?*anyopaque,
) ?*Task {
    const task = heap.gpa.create(Task) catch return null;
    task.* = .{
        .func = func,
        .data = data,
        .on_complete = on_complete,
        .on_complete_user_data = user_data,
        .completed = std.atomic.Value(bool).init(false),
        .handle = null,
        .result = R.ok,
    };
    return task;
}

/// Slot `dispatch`. Queues the body with no completion callback, exactly as `dispatchOnComplete`
/// does, and fails in the same cases.
fn dispatch(
    self_in: ?*abi_task_pool.ke_task_pool,
    func: abi_task_pool.ke_task_func,
    data: ?*anyopaque,
    out_task: ?*?*abi_task_pool.ke_task,
) callconv(.c) abi_result.ke_result {
    return dispatchOnComplete(self_in, func, data, null, null, out_task);
}

/// Slot `dispatch_on_complete`. Queues a task set that runs the body and writes the `Task` as the
/// `ke_task`. The body may already be running when this returns. A null task pool, body or
/// out-parameter and a destroyed pool are an invalid argument, a calling thread enkiTS does not
/// know is not supported, and an allocation failure is out of memory; each writes a null task with
/// nothing queued and nothing left allocated.
fn dispatchOnComplete(
    self_in: ?*abi_task_pool.ke_task_pool,
    func: abi_task_pool.ke_task_func,
    data: ?*anyopaque,
    on_complete: abi_task_pool.ke_task_on_complete_func,
    user_data: ?*anyopaque,
    out_task: ?*?*abi_task_pool.ke_task,
) callconv(.c) abi_result.ke_result {
    const out = out_task orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or func == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const ets = s.ets orelse return R.code(error.InvalidArgument);
    if (c.enkiGetThreadNum(ets) == c.ENKI_NO_THREAD_NUM) {
        log.warn("dispatch refused: the calling thread is neither a worker nor the thread that created the pool", .{});
        return R.code(error.NotSupported);
    }

    const task = allocTask(func, data, on_complete, user_data) orelse return R.code(error.OutOfMemory);
    const set = c.enkiCreateTaskSet(ets, taskSetExecute) orelse {
        heap.gpa.destroy(task);
        return R.code(error.OutOfMemory);
    };
    task.handle = set;

    c.enkiAddTaskSetArgs(ets, set, task, 1);
    out.* = @ptrCast(task);
    return R.ok;
}

/// Slot `wait`. Blocks until enkiTS reports the task finished, then frees the `Task` and returns
/// what its body returned. Afterwards the task refers to freed memory, so a task is waited
/// on once. A null or destroyed task pool and a null task are an invalid argument; a calling thread
/// enkiTS does not know is not supported and leaves the task to be waited on again.
fn wait(self_in: ?*abi_task_pool.ke_task_pool, task_in: ?*abi_task_pool.ke_task) callconv(.c) abi_result.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const task_c = task_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const ets = s.ets orelse return R.code(error.InvalidArgument);
    if (c.enkiGetThreadNum(ets) == c.ENKI_NO_THREAD_NUM) {
        log.warn("wait refused: the calling thread is neither a worker nor the thread that created the pool", .{});
        return R.code(error.NotSupported);
    }

    const task: *Task = @ptrCast(@alignCast(task_c));
    const set: ?*c.enkiTaskSet = @ptrCast(@alignCast(task.handle));
    c.enkiWaitForTaskSet(ets, set);
    c.enkiDeleteTaskSet(ets, set);
    const result = task.result;
    heap.gpa.destroy(task);
    return result;
}

/// Slot `is_completed`. Reads `completed` without ending the task, so the task stays usable until
/// `wait` runs. A null task reports true.
fn isCompleted(self_in: ?*abi_task_pool.ke_task_pool, task_in: ?*abi_task_pool.ke_task) callconv(.c) bool {
    _ = self_in;
    const task_c = task_in orelse return true;
    const task: *Task = @ptrCast(@alignCast(task_c));
    return task.completed.load(.acquire);
}

/// Slot `get_num_workers`. The enkiTS thread count includes the calling thread, which is not
/// counted as a worker. A null or destroyed task pool reports 0.
fn getNumWorkers(self_in: ?*abi_task_pool.ke_task_pool) callconv(.c) u32 {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    const ets = stateOf(self).ets orelse return 0;
    const total = c.enkiGetNumTaskThreads(ets);
    return if (total > 0) total - 1 else 0;
}

/// The handle's `destroy`. Waits for everything enkiTS holds, deletes the enkiTS object and
/// frees the `State`. `Task` allocations of tasks that were never waited on are not freed here.
/// A null task pool is ignored.
fn destroy(self_in: ?*abi_task_pool.ke_task_pool) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.ets) |ets| {
        c.enkiWaitForAll(ets);
        c.enkiDeleteTaskScheduler(ets);
        s.ets = null;
    }
    heap.gpa.destroy(s);
}

/// The factory. A `worker_count` of 0, or no params, lets enkiTS size the pool from the hardware;
/// any other count is the workers besides the calling thread, which enkiTS counts as one of its
/// threads. Fails with out of memory when the `State` cannot be allocated and general when the
/// enkiTS object cannot be created, leaving nothing allocated and the handle zeroed.
export fn ke_task_pool_enki_create(params_in: ?*const abi_task_pool_enki_factory.ke_task_pool_enki_params, out_task_pool: ?*abi_task_pool.ke_task_pool_handle) callconv(.c) abi_result.ke_result {
    const out = out_task_pool orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_task_pool.ke_task_pool_handle);
    out.* = create(params_in) catch |err| {
        log.warn("creating the task pool failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(params_in: ?*const abi_task_pool_enki_factory.ke_task_pool_enki_params) R.Error!abi_task_pool.ke_task_pool_handle {
    const s = heap.gpa.create(State) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(s);
    s.* = .{ .api = std.mem.zeroes(abi_task_pool.ke_task_pool), .ets = null };

    s.ets = c.enkiNewTaskScheduler() orelse return error.General;
    const worker_count: u32 = if (params_in) |p| p.*.worker_count else 0;
    if (worker_count == 0) c.enkiInitTaskScheduler(s.ets) else c.enkiInitTaskSchedulerNumThreads(s.ets, worker_count + 1);

    s.api.handle = s;
    s.api.dispatch = dispatch;
    s.api.dispatch_on_complete = dispatchOnComplete;
    s.api.wait = wait;
    s.api.is_completed = isCompleted;
    s.api.get_num_workers = getNumWorkers;

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;

const Flag = std.atomic.Value(bool);
const Counter = std.atomic.Value(i32);

fn setFlag(data: ?*anyopaque) callconv(.c) abi_result.ke_result {
    const flag: *Flag = @ptrCast(@alignCast(data.?));
    flag.store(true, .release);
    return R.ok;
}

fn setFlagOnComplete(task_in: ?*abi_task_pool.ke_task, user_data: ?*anyopaque, result: abi_result.ke_result) callconv(.c) void {
    _ = task_in;
    _ = result;
    const flag: *Flag = @ptrCast(@alignCast(user_data.?));
    flag.store(true, .release);
}

fn spinUntilFlag(data: ?*anyopaque) callconv(.c) abi_result.ke_result {
    const flag: *Flag = @ptrCast(@alignCast(data.?));
    while (!flag.load(.acquire)) std.atomic.spinLoopHint();
    return R.ok;
}

fn writeAnswer(data: ?*anyopaque) callconv(.c) abi_result.ke_result {
    const value: *i32 = @ptrCast(@alignCast(data.?));
    value.* = 42;
    return R.ok;
}

fn incrementCounter(data: ?*anyopaque) callconv(.c) abi_result.ke_result {
    const counter: *Counter = @ptrCast(@alignCast(data.?));
    _ = counter.fetchAdd(1, .acq_rel);
    return R.ok;
}

fn failWithNotFound(data: ?*anyopaque) callconv(.c) abi_result.ke_result {
    _ = data;
    return R.code(error.NotFound);
}

fn recordCompletionFailure(task_in: ?*abi_task_pool.ke_task, user_data: ?*anyopaque, result: abi_result.ke_result) callconv(.c) void {
    _ = task_in;
    const seen: *abi_result.ke_result = @ptrCast(@alignCast(user_data.?));
    seen.* = result;
}

fn created(params: ?*const abi_task_pool_enki_factory.ke_task_pool_enki_params) !abi_task_pool.ke_task_pool_handle {
    var h: abi_task_pool.ke_task_pool_handle = undefined;
    try R.check(ke_task_pool_enki_create(params, &h));
    return h;
}

test "a task that fails hands its code to the thread that waits on it" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var task: ?*abi_task_pool.ke_task = null;
    try R.check(h.ref.?.dispatch.?(h.ref, failWithNotFound, null, &task));

    try testing.expectError(error.NotFound, R.check(h.ref.?.wait.?(h.ref, task)));
}

test "a task that succeeds hands OK to the thread that waits on it" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var ran = Flag.init(false);
    var task: ?*abi_task_pool.ke_task = null;
    try R.check(h.ref.?.dispatch.?(h.ref, setFlag, &ran, &task));

    try testing.expectEqual(R.ok, h.ref.?.wait.?(h.ref, task));
}

test "a completion callback is handed the code the body returned" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var seen: abi_result.ke_result = R.ok;
    var task: ?*abi_task_pool.ke_task = null;
    try R.check(h.ref.?.dispatch_on_complete.?(h.ref, failWithNotFound, null, recordCompletionFailure, @ptrCast(&seen), &task));

    try testing.expectError(error.NotFound, R.check(h.ref.?.wait.?(h.ref, task)));
    try testing.expectError(error.NotFound, R.check(seen));
}

test "a dispatched task runs and reports completion" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var ran = Flag.init(false);
    var task: ?*abi_task_pool.ke_task = null;
    try R.check(h.ref.?.dispatch.?(h.ref, setFlag, &ran, &task));

    try testing.expectEqual(R.ok, h.ref.?.wait.?(h.ref, task));
    try testing.expect(ran.load(.acquire));
}

test "a completion callback fires after the task body" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var ran = Flag.init(false);
    var completed = Flag.init(false);

    var task: ?*abi_task_pool.ke_task = null;
    try R.check(h.ref.?.dispatch_on_complete.?(h.ref, setFlag, &ran, setFlagOnComplete, &completed, &task));

    try testing.expectEqual(R.ok, h.ref.?.wait.?(h.ref, task));
    try testing.expect(ran.load(.acquire));
    try testing.expect(completed.load(.acquire));
}

test "a task flips to completed while it is still waited on" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var can_finish = Flag.init(false);
    var task: ?*abi_task_pool.ke_task = null;
    try R.check(h.ref.?.dispatch.?(h.ref, spinUntilFlag, &can_finish, &task));

    can_finish.store(true, .release);
    while (!h.ref.?.is_completed.?(h.ref, task)) std.atomic.spinLoopHint();
    try testing.expectEqual(R.ok, h.ref.?.wait.?(h.ref, task));
}

test "user data reaches the task body unchanged" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var value: i32 = 0;
    var task: ?*abi_task_pool.ke_task = null;
    try R.check(h.ref.?.dispatch.?(h.ref, writeAnswer, &value, &task));

    try testing.expectEqual(R.ok, h.ref.?.wait.?(h.ref, task));
    try testing.expectEqual(@as(i32, 42), value);
}

test "ten dispatched tasks all execute" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var counter = Counter.init(0);
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var task: ?*abi_task_pool.ke_task = null;
        try R.check(h.ref.?.dispatch.?(h.ref, incrementCounter, &counter, &task));
        try testing.expectEqual(R.ok, h.ref.?.wait.?(h.ref, task));
    }

    try testing.expectEqual(@as(i32, 10), counter.load(.acquire));
}

fn dispatchFromOutside(pool: *abi_task_pool.ke_task_pool, task: *?*abi_task_pool.ke_task, code: *abi_result.ke_result) void {
    code.* = pool.dispatch.?(pool, failWithNotFound, null, task);
}

fn waitFromOutside(pool: *abi_task_pool.ke_task_pool, task: ?*abi_task_pool.ke_task, out: *abi_result.ke_result) void {
    out.* = pool.wait.?(pool, task);
}

test "a thread outside the pool cannot dispatch" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var task: ?*abi_task_pool.ke_task = undefined;
    var code: abi_result.ke_result = R.ok;
    const thread = try std.Thread.spawn(.{}, dispatchFromOutside, .{ h.ref.?, &task, &code });
    thread.join();
    try testing.expectError(error.NotSupported, R.check(code));
    try testing.expect(task == null);
}

test "a thread outside the pool cannot wait, and the task stays waitable from the pool's threads" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var task: ?*abi_task_pool.ke_task = null;
    try R.check(h.ref.?.dispatch.?(h.ref, failWithNotFound, null, &task));

    var code: abi_result.ke_result = R.ok;
    const thread = try std.Thread.spawn(.{}, waitFromOutside, .{ h.ref.?, task, &code });
    thread.join();
    try testing.expectError(error.NotSupported, R.check(code));

    try testing.expectError(error.NotFound, R.check(h.ref.?.wait.?(h.ref, task)));
}

test "dispatch refuses a null task pool, task function or out-parameter as an invalid argument" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var task: ?*abi_task_pool.ke_task = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.dispatch.?(null, null, null, &task)));
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.dispatch.?(h.ref, null, null, &task)));
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.dispatch.?(h.ref, setFlag, null, null)));
    try testing.expect(task == null);
}

test "dispatch on complete refuses a null task pool or task function as an invalid argument" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    var task: ?*abi_task_pool.ke_task = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.dispatch_on_complete.?(null, null, null, null, null, &task)));
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.dispatch_on_complete.?(h.ref, null, null, null, null, &task)));
    try testing.expect(task == null);
}

test "wait refuses a null task pool and a null task as an invalid argument" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.wait.?(null, null)));
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.wait.?(h.ref, null)));
}

test "a null task counts as completed" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.?.is_completed.?(h.ref, null));
}

test "the worker count excludes the calling thread" {
    const h = try created(null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.?.get_num_workers.?(h.ref) >= 1);
    try testing.expectEqual(@as(u32, 0), h.ref.?.get_num_workers.?(null));
}

test "a worker count in the params sizes the pool" {
    var params = std.mem.zeroes(abi_task_pool_enki_factory.ke_task_pool_enki_params);
    params.worker_count = 3;
    const h = try created(&params);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(@as(u32, 3), h.ref.?.get_num_workers.?(h.ref));
}

test "a null handle to fill is refused as an invalid argument" {
    try testing.expectError(error.InvalidArgument, R.check(ke_task_pool_enki_create(null, null)));
}

test "destroying a null task pool is safe" {
    const h = try created(null);

    h.destroy.?(h.ref);
    h.destroy.?(null);
}

test "creating and destroying a task pool leaves no block allocated" {
    const h = try created(null);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

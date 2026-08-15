const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

/// ke_task* is opaque to callers, so the pinned/regular distinction rides in
/// its low bit — both Task allocations are at least 2-byte aligned, leaving it
/// free. wait() and is_completed() need it to pick the right enkiTS call.
const pinned_tag: usize = 1;

const Task = struct {
    func: c.ke_task_func,
    data: ?*anyopaque,
    on_complete: c.ke_task_on_complete_func,
    on_complete_user_data: ?*anyopaque,
    completed: std.atomic.Value(bool),
    /// Either an enkiTaskSet* or an enkiPinnedTask*, matching the tag.
    handle: ?*anyopaque,
    /// Set once, before the task is scheduled; read by the worker thread.
    tagged_self: ?*c.ke_task,

    fn run(self: *Task) void {
        if (self.func) |f| f(self.data);
        self.completed.store(true, .release);
        if (self.on_complete) |done| done(self.tagged_self, self.on_complete_user_data);
    }
};

const State = struct {
    api: c.ke_scheduler,
    ets: ?*c.enkiTaskScheduler,
};

fn stateOf(self: *c.ke_scheduler) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn tag(task: *Task, pinned: bool) *c.ke_task {
    const raw = @intFromPtr(task) | (if (pinned) pinned_tag else 0);
    return @ptrFromInt(raw);
}

fn untag(task: *c.ke_task) struct { task: *Task, pinned: bool } {
    const raw = @intFromPtr(task);
    return .{
        .task = @ptrFromInt(raw & ~pinned_tag),
        .pinned = (raw & pinned_tag) != 0,
    };
}

fn taskSetExecute(start: u32, end: u32, threadnum: u32, args: ?*anyopaque) callconv(.c) void {
    _ = start;
    _ = end;
    _ = threadnum;
    const task: *Task = @ptrCast(@alignCast(args orelse return));
    task.run();
}

fn pinnedTaskExecute(args: ?*anyopaque) callconv(.c) void {
    const task: *Task = @ptrCast(@alignCast(args orelse return));
    task.run();
}

fn allocTask(
    func: c.ke_task_func,
    data: ?*anyopaque,
    on_complete: c.ke_task_on_complete_func,
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
        .tagged_self = null,
    };
    return task;
}

fn dispatch(
    self_in: ?*c.ke_scheduler,
    func: c.ke_task_func,
    data: ?*anyopaque,
) callconv(.c) ?*c.ke_task {
    const self = self_in orelse return null;
    return dispatchOnComplete(self, func, data, null, null);
}

fn dispatchOnComplete(
    self_in: ?*c.ke_scheduler,
    func: c.ke_task_func,
    data: ?*anyopaque,
    on_complete: c.ke_task_on_complete_func,
    user_data: ?*anyopaque,
) callconv(.c) ?*c.ke_task {
    const self = self_in orelse return null;
    if (self.handle == null or func == null) return null;
    const s = stateOf(self);
    const ets = s.ets orelse return null;

    const task = allocTask(func, data, on_complete, user_data) orelse return null;
    const set = c.enkiCreateTaskSet(ets, taskSetExecute) orelse {
        heap.gpa.destroy(task);
        return null;
    };
    task.handle = set;
    task.tagged_self = tag(task, false);

    c.enkiAddTaskSetArgs(ets, set, task, 1);
    return task.tagged_self;
}

fn dispatchPinned(
    self_in: ?*c.ke_scheduler,
    thread_num: u32,
    func: c.ke_task_func,
    data: ?*anyopaque,
) callconv(.c) ?*c.ke_task {
    const self = self_in orelse return null;
    if (self.handle == null or func == null) return null;
    const s = stateOf(self);
    const ets = s.ets orelse return null;

    const task = allocTask(func, data, null, null) orelse return null;
    const pinned = c.enkiCreatePinnedTask(ets, pinnedTaskExecute, thread_num) orelse {
        heap.gpa.destroy(task);
        return null;
    };
    task.handle = pinned;
    task.tagged_self = tag(task, true);

    c.enkiAddPinnedTaskArgs(ets, pinned, task);
    return task.tagged_self;
}

fn wait(self_in: ?*c.ke_scheduler, task_in: ?*c.ke_task) callconv(.c) void {
    const self = self_in orelse return;
    const tagged = task_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    const ets = s.ets orelse return;

    const t = untag(tagged);
    if (t.pinned) {
        const pinned: ?*c.enkiPinnedTask = @ptrCast(@alignCast(t.task.handle));
        c.enkiWaitForPinnedTask(ets, pinned);
        c.enkiDeletePinnedTask(ets, pinned);
    } else {
        const set: ?*c.enkiTaskSet = @ptrCast(@alignCast(t.task.handle));
        c.enkiWaitForTaskSet(ets, set);
        c.enkiDeleteTaskSet(ets, set);
    }
    heap.gpa.destroy(t.task);
}

fn isCompleted(self_in: ?*c.ke_scheduler, task_in: ?*c.ke_task) callconv(.c) bool {
    _ = self_in;
    const tagged = task_in orelse return true;
    return untag(tagged).task.completed.load(.acquire);
}

fn getNumWorkers(self_in: ?*c.ke_scheduler) callconv(.c) u32 {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    const ets = stateOf(self).ets orelse return 0;
    const total = c.enkiGetNumTaskThreads(ets);
    return if (total > 0) total - 1 else 0;
}

fn destroy(self_in: ?*c.ke_scheduler) callconv(.c) void {
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

export fn ke_scheduler_enki_create(out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_scheduler_handle {
    const null_handle = std.mem.zeroes(c.ke_scheduler_handle);

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "allocation failed", @src());
        return null_handle;
    };
    s.* = .{ .api = std.mem.zeroes(c.ke_scheduler), .ets = null };

    s.ets = c.enkiNewTaskScheduler() orelse {
        heap.gpa.destroy(s);
        E.fail(out_error, .general, "task scheduler creation failed", @src());
        return null_handle;
    };
    c.enkiInitTaskScheduler(s.ets);

    s.api.handle = s;
    s.api.dispatch = dispatch;
    s.api.dispatch_on_complete = dispatchOnComplete;
    s.api.wait = wait;
    s.api.is_completed = isCompleted;
    s.api.dispatch_pinned = dispatchPinned;
    s.api.get_num_workers = getNumWorkers;

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;

const Flag = std.atomic.Value(bool);
const Counter = std.atomic.Value(i32);

fn setFlag(data: ?*anyopaque) callconv(.c) void {
    const flag: *Flag = @ptrCast(@alignCast(data.?));
    flag.store(true, .release);
}

fn setFlagOnComplete(task_in: ?*c.ke_task, user_data: ?*anyopaque) callconv(.c) void {
    _ = task_in;
    const flag: *Flag = @ptrCast(@alignCast(user_data.?));
    flag.store(true, .release);
}

fn spinUntilFlag(data: ?*anyopaque) callconv(.c) void {
    const flag: *Flag = @ptrCast(@alignCast(data.?));
    while (!flag.load(.acquire)) std.atomic.spinLoopHint();
}

fn writeAnswer(data: ?*anyopaque) callconv(.c) void {
    const value: *i32 = @ptrCast(@alignCast(data.?));
    value.* = 42;
}

fn incrementCounter(data: ?*anyopaque) callconv(.c) void {
    const counter: *Counter = @ptrCast(@alignCast(data.?));
    _ = counter.fetchAdd(1, .acq_rel);
}

test "a dispatched task runs and reports completion" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var ran = Flag.init(false);
    const task = h.ref.*.dispatch.?(h.ref, setFlag, &ran);
    try testing.expect(task != null);

    h.ref.*.wait.?(h.ref, task);
    try testing.expect(ran.load(.acquire));
}

test "a completion callback fires after the task body" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var ran = Flag.init(false);
    var completed = Flag.init(false);

    const task = h.ref.*.dispatch_on_complete.?(h.ref, setFlag, &ran, setFlagOnComplete, &completed);
    try testing.expect(task != null);

    h.ref.*.wait.?(h.ref, task);
    try testing.expect(ran.load(.acquire));
    try testing.expect(completed.load(.acquire));
}

test "a task flips to completed while it is still waited on" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var can_finish = Flag.init(false);
    const task = h.ref.*.dispatch.?(h.ref, spinUntilFlag, &can_finish);
    try testing.expect(task != null);

    can_finish.store(true, .release);
    while (!h.ref.*.is_completed.?(h.ref, task)) std.atomic.spinLoopHint();
    h.ref.*.wait.?(h.ref, task);
}

test "user data reaches the task body unchanged" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var value: i32 = 0;
    const task = h.ref.*.dispatch.?(h.ref, writeAnswer, &value);
    try testing.expect(task != null);

    h.ref.*.wait.?(h.ref, task);
    try testing.expectEqual(@as(i32, 42), value);
}

test "ten dispatched tasks all execute" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var counter = Counter.init(0);
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const task = h.ref.*.dispatch.?(h.ref, incrementCounter, &counter);
        try testing.expect(task != null);
        h.ref.*.wait.?(h.ref, task);
    }

    try testing.expectEqual(@as(i32, 10), counter.load(.acquire));
}

test "dispatch refuses a null scheduler or a null task function" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.dispatch.?(null, null, null) == null);
    try testing.expect(h.ref.*.dispatch.?(h.ref, null, null) == null);
}

test "dispatch on complete refuses a null scheduler or a null task function" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.dispatch_on_complete.?(null, null, null, null, null) == null);
    try testing.expect(h.ref.*.dispatch_on_complete.?(h.ref, null, null, null, null) == null);
}

test "wait tolerates a null scheduler and a null task" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    h.ref.*.wait.?(null, null);
    h.ref.*.wait.?(h.ref, null);
}

test "a null task counts as completed" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.is_completed.?(h.ref, null));
}

test "the worker count excludes the calling thread" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.get_num_workers.?(h.ref) >= 1);
    try testing.expectEqual(@as(u32, 0), h.ref.*.get_num_workers.?(null));
}

test "a pinned task runs on its worker and reports completion" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var ran = Flag.init(false);
    const task = h.ref.*.dispatch_pinned.?(h.ref, 0, setFlag, &ran);
    try testing.expect(task != null);

    h.ref.*.wait.?(h.ref, task);
    try testing.expect(ran.load(.acquire));
    try testing.expect(h.ref.*.dispatch_pinned.?(h.ref, 0, null, null) == null);
}

test "destroying a null scheduler is safe" {
    const h = ke_scheduler_enki_create(null);
    try testing.expect(h.ref != null);

    h.destroy.?(h.ref);
    h.destroy.?(null);
}

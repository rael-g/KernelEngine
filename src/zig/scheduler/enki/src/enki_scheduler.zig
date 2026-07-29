// ke_scheduler backed by enkiTS, through enkiTS's C API.
//
// enkiTS carries per-task state as a void* argument rather than by subclassing,
// so each dispatch allocates a Task that owns both the enkiTS handle and the
// callback it must run. The ke_task* handed back to the caller is that Task.

const std = @import("std");

// This .so is dlopen'd by a foreign, non-Zig host alongside many sibling
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack exceeds glibc's small static-TLS surplus once enough plugins
// accumulate, aborting with "cannot allocate memory in static TLS block".
pub const std_options: std.Options = .{ .signal_stack_size = null };

// Windows: mingw's crtdll must own the DLL entry point so the statically
// linked C/C++ dependency's initializers actually run. See kerror.zig.
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

// -- enkiTS entry points -----------------------------------------------------

fn taskSetExecute(start: u32, end: u32, threadnum: u32, args: ?*anyopaque) callconv(.c) void {
    _ = start;
    _ = end;
    _ = threadnum;
    // The engine's task contract is a single call, not a partitioned range, so
    // the set size stays 1 and the range bounds are ignored.
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

// -- vtable ------------------------------------------------------------------

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

    // The worker may run and complete the task before this call returns, so
    // everything it reads must already be in place.
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
    // wait() is the task's teardown point, matching the contract callers rely
    // on: the handle is dead once it returns.
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
    // enkiTS counts the calling thread (id 0) among its task threads; workers
    // are 1..N-1.
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

// -- factory -----------------------------------------------------------------

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

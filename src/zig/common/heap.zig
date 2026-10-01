const std = @import("std");

const tracking = @import("builtin").mode == .Debug;

var debug_instance: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
var live_instances = std.atomic.Value(usize).init(0);
var leak_reports = std.atomic.Value(usize).init(0);

pub const gpa: std.mem.Allocator = if (tracking)
    debug_instance.allocator()
else
    std.heap.smp_allocator;

pub fn retain() void {
    if (!tracking) return;
    _ = live_instances.fetchAdd(1, .monotonic);
}

pub fn release() void {
    if (!tracking) return;

    var live = live_instances.load(.monotonic);
    while (live != 0) {
        live = live_instances.cmpxchgWeak(live, live - 1, .acq_rel, .monotonic) orelse break;
    } else return;
    if (live != 1) return;

    if (debug_instance.deinit() == .leak) _ = leak_reports.fetchAdd(1, .monotonic);
    debug_instance = .init;
}

pub fn leakReports() usize {
    return leak_reports.load(.monotonic);
}

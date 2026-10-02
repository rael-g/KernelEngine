const std = @import("std");

const tracking = @import("builtin").mode == .Debug;

/// Every plugin root module that imports this module re-exports it: `pub const _DllMainCRTStartup = @import("heap")._DllMainCRTStartup;`.
pub extern fn _DllMainCRTStartup(
    hinst: std.os.windows.HINSTANCE,
    reason: std.os.windows.DWORD,
    reserved: std.os.windows.LPVOID,
) callconv(.winapi) std.os.windows.BOOL;

extern "c" fn atexit(callback: *const fn () callconv(.c) void) c_int;

var debug_instance: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
var exit_hook = std.atomic.Value(bool).init(false);

fn reportLeaksAtExit() callconv(.c) void {
    _ = debug_instance.deinit();
}

fn registerExitHook() void {
    if (exit_hook.swap(true, .acq_rel)) return;
    _ = atexit(&reportLeaksAtExit);
}

fn trackedAlloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    registerExitHook();
    const inner = debug_instance.allocator();
    return inner.vtable.alloc(inner.ptr, len, alignment, ret_addr);
}

fn trackedResize(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const inner = debug_instance.allocator();
    return inner.vtable.resize(inner.ptr, memory, alignment, new_len, ret_addr);
}

fn trackedRemap(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const inner = debug_instance.allocator();
    return inner.vtable.remap(inner.ptr, memory, alignment, new_len, ret_addr);
}

fn trackedFree(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    const inner = debug_instance.allocator();
    inner.vtable.free(inner.ptr, memory, alignment, ret_addr);
}

const tracked_vtable: std.mem.Allocator.VTable = .{
    .alloc = trackedAlloc,
    .resize = trackedResize,
    .remap = trackedRemap,
    .free = trackedFree,
};

pub const gpa: std.mem.Allocator = if (tracking)
    .{ .ptr = undefined, .vtable = &tracked_vtable }
else
    std.heap.smp_allocator;

pub fn leaks() usize {
    if (!tracking) return 0;
    return debug_instance.detectLeaks();
}

pub fn expectNoLeaks() !void {
    try std.testing.expectEqual(@as(usize, 0), leaks());
}

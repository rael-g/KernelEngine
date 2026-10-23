//! Where one plugin library's `std.log` goes: to the callback the host set through the library's
//! exported `<library>_set_log_callback`, or to stderr while none is set.

const std = @import("std");

/// The C type `ke_log_callback` of `kernel_engine/logger/log_callback.h`.
pub const Callback = *const fn (ctx: ?*anyopaque, level: c_int, scope: [*:0]const u8, message: [*:0]const u8) callconv(.c) void;

/// The `ke_log_level` value each `std.log` level is handed to the callback as.
fn levelOf(level: std.log.Level) c_int {
    return switch (level) {
        .err => 4,
        .warn => 3,
        .info => 2,
        .debug => 1,
    };
}

/// The log destination of the library named `library`, as its exported symbols spell it (for
/// example "ke_render_forward"). Referencing `logFn` from the library root's `std_options` also
/// exports `<library>_set_log_callback`. The setter publishes the callback and its context as one
/// pair, so a line is never written with one setting's callback and another's context; it is meant
/// to be called once, before the library logs, and a later call does not wait for lines in flight.
pub fn Destination(comptime library: []const u8) type {
    return struct {
        const Target = struct { callback: Callback, ctx: ?*anyopaque };

        var slots: [2]Target = undefined;
        var next_slot: usize = 0;
        var current: std.atomic.Value(?*const Target) = .init(null);

        /// Slot `<library>_set_log_callback`. A null callback sends the library's lines back to stderr.
        fn setLogCallback(callback: ?Callback, ctx: ?*anyopaque) callconv(.c) void {
            const cb = callback orelse {
                current.store(null, .release);
                return;
            };
            const slot = &slots[next_slot];
            next_slot = 1 - next_slot;
            slot.* = .{ .callback = cb, .ctx = ctx };
            current.store(slot, .release);
        }

        comptime {
            @export(&setLogCallback, .{ .name = library ++ "_set_log_callback" });
        }

        /// The `logFn` of the library's `std_options`. Formats the line and hands it to the
        /// callback with the scope's name; writes it as `std.log` would by default when no callback
        /// is set or the line cannot be formatted.
        pub fn logFn(
            comptime level: std.log.Level,
            comptime scope: @EnumLiteral(),
            comptime format: []const u8,
            args: anytype,
        ) void {
            const target = current.load(.acquire) orelse return std.log.defaultLog(level, scope, format, args);
            var fallback = std.heap.stackFallback(512, std.heap.page_allocator);
            const allocator = fallback.get();
            const line = std.fmt.allocPrintSentinel(allocator, format, args, 0) catch
                return std.log.defaultLog(level, scope, format, args);
            defer allocator.free(line);
            target.callback(target.ctx, levelOf(level), @tagName(scope), line.ptr);
        }
    };
}

const testing = std.testing;

const Captured = struct {
    var level: c_int = 0;
    var scope: [32]u8 = undefined;
    var scope_len: usize = 0;
    var message: [64]u8 = undefined;
    var message_len: usize = 0;
    var ctx_seen: ?*anyopaque = null;

    fn record(ctx: ?*anyopaque, level_in: c_int, scope_in: [*:0]const u8, message_in: [*:0]const u8) callconv(.c) void {
        ctx_seen = ctx;
        level = level_in;
        const s = std.mem.span(scope_in);
        @memcpy(scope[0..s.len], s);
        scope_len = s.len;
        const m = std.mem.span(message_in);
        @memcpy(message[0..m.len], m);
        message_len = m.len;
    }
};

const Probe = Destination("ke_log_probe");

test "a line goes to the callback the host set, with its level, scope, message and context" {
    var marker: u8 = 0;
    Probe.setLogCallback(Captured.record, &marker);
    defer Probe.setLogCallback(null, null);

    Probe.logFn(.warn, .forward, "pipeline {s} took {d} ms", .{ "lit", 12 });

    try testing.expectEqual(@as(c_int, 3), Captured.level);
    try testing.expectEqualStrings("forward", Captured.scope[0..Captured.scope_len]);
    try testing.expectEqualStrings("pipeline lit took 12 ms", Captured.message[0..Captured.message_len]);
    try testing.expectEqual(@as(?*anyopaque, &marker), Captured.ctx_seen);
}

test "each std.log level reaches the callback as the ke_log_level of the same name" {
    try testing.expectEqual(@as(c_int, 4), levelOf(.err));
    try testing.expectEqual(@as(c_int, 3), levelOf(.warn));
    try testing.expectEqual(@as(c_int, 2), levelOf(.info));
    try testing.expectEqual(@as(c_int, 1), levelOf(.debug));
}

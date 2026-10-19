//! The logger that fans each event out to a set of sinks, and the console sink that writes to
//! stderr.

const std = @import("std");
const testing = std.testing;

pub const std_options: std.Options = .{ .signal_stack_size = null };

const heap = @import("heap");
const gpa = heap.gpa;

const c = @import("c");

const E = @import("kerror").Errors(c);

/// Reached through the `handle` of the logger, allocated by `ke_logger_create` and freed by
/// `loggerDestroy`. The sinks are visited in the order they were added, nothing is locked, and a
/// sink runs on the thread that called the logger, so a sink is added before the logger is shared.
const State = struct {
    sinks: std.ArrayList(c.ke_logger_sink),
};

/// The destroy function of the handle `ke_logger_create` returns. Sinks are destroyed while the
/// state still holds them; both allocations are freed on return, so the logger and its state are
/// invalid afterwards.
fn loggerDestroy(self: ?*c.ke_logger) callconv(.c) void {
    const logger = self orelse return;
    const s: *State = @ptrCast(@alignCast(logger.handle));
    for (s.sinks.items) |*sink| {
        if (sink.destroy) |d| d(sink);
    }
    s.sinks.deinit(gpa);
    gpa.destroy(s);
    gpa.destroy(logger);
}

/// Calls the `log` function of each sink whose minimum level the event reaches. A sink without one
/// is skipped, and a null logger or event does nothing.
fn loggerLog(self: ?*c.ke_logger, event: [*c]const c.ke_log_event) callconv(.c) void {
    if (self == null or event == null) return;
    const s: *State = @ptrCast(@alignCast(self.?.handle));
    for (s.sinks.items) |*sink| {
        if (event.*.level >= sink.min_level) {
            if (sink.log) |log| log(sink, event);
        }
    }
}

/// Calls the `flush` function of each sink that has one. A null logger does nothing.
fn loggerFlush(self: ?*c.ke_logger) callconv(.c) void {
    const logger = self orelse return;
    const s: *State = @ptrCast(@alignCast(logger.handle));
    for (s.sinks.items) |*sink| {
        if (sink.flush) |f| f(sink);
    }
}

/// The `add_sink` slot. On success the logger keeps its own copy of the sink, and `loggerDestroy`
/// will call that copy's destroy function. It reports an invalid-argument error for a null logger
/// and an out-of-memory error when the set cannot grow; either way the set is unchanged and the
/// result is false.
fn loggerAddSink(self: ?*c.ke_logger, sink: c.ke_logger_sink, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const logger = self orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    const s: *State = @ptrCast(@alignCast(logger.handle));
    s.sinks.append(gpa, sink) catch {
        E.fail(out_error, .out_of_memory, "sink allocation failed", @src());
        return false;
    };
    return true;
}

fn writeEvent(writer: *std.Io.Writer, event: *const c.ke_log_event) std.Io.Writer.Error!void {
    const label = std.mem.span(levelToString(event.level));
    const tag: []const u8 = if (event.tag != null) std.mem.span(event.tag) else "";
    const message: []const u8 = if (event.message != null) std.mem.span(event.message) else "";
    try writer.print("[{s}] {s}: {s}\n", .{ label, tag, message });
}

fn consoleSinkWrite(event: *const c.ke_log_event) void {
    var buffer: [256]u8 = undefined;
    const locked = std.debug.lockStderr(&buffer);
    defer std.debug.unlockStderr();
    const writer = &locked.file_writer.interface;
    writeEvent(writer, event) catch return;
    writer.flush() catch return;
}

/// The `log` slot of the console sink. A null event does nothing; a failed write to stderr is
/// dropped, since the sink has nowhere to report it.
fn consoleSinkLog(self: ?*c.ke_logger_sink, event: [*c]const c.ke_log_event) callconv(.c) void {
    _ = self;
    if (event == null) return;
    consoleSinkWrite(&event.*);
}

/// Nothing to flush: `consoleSinkWrite` flushes stderr after every entry.
fn consoleSinkFlush(self: ?*c.ke_logger_sink) callconv(.c) void {
    _ = self;
}

/// Nothing to release: the sink holds no handle and writes to the process's stderr.
fn consoleSinkDestroy(self: ?*c.ke_logger_sink) callconv(.c) void {
    _ = self;
}

/// Returns the sink by value, with no handle and the trace level as its minimum, so the level
/// filter of a logger it is added to admits every level the enum defines.
export fn ke_console_sink_create() callconv(.c) c.ke_logger_sink {
    return .{
        .handle = null,
        .min_level = c.KE_LOG_LEVEL_TRACE,
        .log = &consoleSinkLog,
        .flush = &consoleSinkFlush,
        .destroy = &consoleSinkDestroy,
    };
}

fn levelToString(level: i32) [*c]const u8 {
    return switch (level) {
        c.KE_LOG_LEVEL_TRACE => "TRACE",
        c.KE_LOG_LEVEL_DEBUG => "DEBUG",
        c.KE_LOG_LEVEL_INFO => "INFO",
        c.KE_LOG_LEVEL_WARNING => "WARNING",
        c.KE_LOG_LEVEL_ERROR => "ERROR",
        c.KE_LOG_LEVEL_CRITICAL => "CRITICAL",
        else => "UNKNOWN",
    };
}

/// Returns a handle whose `ref` is the new logger and whose `destroy` is `loggerDestroy`. If the
/// state allocation fails, the logger is freed, the handle comes back with a null `ref` and a null
/// `destroy`, and `out_error` receives an out-of-memory error.
export fn ke_logger_create(out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_logger_handle {
    const empty = c.ke_logger_handle{ .ref = null, .destroy = null };

    const logger = gpa.create(c.ke_logger) catch {
        E.fail(out_error, .out_of_memory, "logger allocation failed", @src());
        return empty;
    };
    const state = gpa.create(State) catch {
        gpa.destroy(logger);
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return empty;
    };
    state.* = .{ .sinks = .empty };

    logger.handle = state;
    logger.log = &loggerLog;
    logger.flush = &loggerFlush;
    logger.add_sink = &loggerAddSink;

    return .{ .ref = logger, .destroy = &loggerDestroy };
}

fn countingSinkLog(self: ?*c.ke_logger_sink, event: [*c]const c.ke_log_event) callconv(.c) void {
    if (self == null or event == null) return;
    const p: *i32 = @ptrCast(@alignCast(self.?.handle.?));
    p.* += 1;
}

fn countingSinkDestroy(self: ?*c.ke_logger_sink) callconv(.c) void {
    if (self == null) return;
    const p: *i32 = @ptrCast(@alignCast(self.?.handle.?));
    p.* += 1;
}

test "create returns a usable handle" {
    const h = ke_logger_create(null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
}

test "destroy tolerates a null logger" {
    const h = ke_logger_create(null);
    const destroy_fn = h.destroy.?;
    destroy_fn(null);
    destroy_fn(h.ref);
}

test "destroy works when sinks are attached" {
    const h = ke_logger_create(null);
    defer h.destroy.?(h.ref);

    var sink = std.mem.zeroes(c.ke_logger_sink);
    sink.min_level = c.KE_LOG_LEVEL_TRACE;
    sink.log = &consoleSinkLog;
    sink.destroy = &consoleSinkDestroy;

    const result = h.ref.*.add_sink.?(h.ref, sink, null);
    try testing.expect(result);
}

test "log tolerates a null self" {
    var ev = std.mem.zeroes(c.ke_log_event);
    ev.level = c.KE_LOG_LEVEL_INFO;
    ev.tag = "TEST";
    ev.message = "Message";

    const logger = ke_logger_create(null);
    defer logger.destroy.?(logger.ref);

    logger.ref.*.log.?(null, &ev);
}

test "log tolerates a null event" {
    const logger = ke_logger_create(null);
    defer logger.destroy.?(logger.ref);

    logger.ref.*.log.?(logger.ref, null);
}

test "add_sink on a null self returns false" {
    const h = ke_logger_create(null);
    defer h.destroy.?(h.ref);
    var sink = std.mem.zeroes(c.ke_logger_sink);
    sink.min_level = c.KE_LOG_LEVEL_TRACE;
    sink.log = &consoleSinkLog;

    const result = h.ref.*.add_sink.?(null, sink, null);
    try testing.expect(!result);
}

test "a sink whose minimum level is met receives the event" {
    var counter: i32 = 0;

    var sink = std.mem.zeroes(c.ke_logger_sink);
    sink.handle = &counter;
    sink.min_level = c.KE_LOG_LEVEL_INFO;
    sink.log = &countingSinkLog;

    const logger = ke_logger_create(null);
    defer logger.destroy.?(logger.ref);

    const result = logger.ref.*.add_sink.?(logger.ref, sink, null);
    try testing.expect(result);

    var ev = std.mem.zeroes(c.ke_log_event);
    ev.level = c.KE_LOG_LEVEL_INFO;
    ev.tag = "TEST";
    ev.message = "Message";

    logger.ref.*.log.?(logger.ref, &ev);

    try testing.expectEqual(@as(i32, 1), counter);
}

test "a sink whose minimum level is above the event is not called" {
    var counter: i32 = 0;

    var sink = std.mem.zeroes(c.ke_logger_sink);
    sink.handle = &counter;
    sink.min_level = c.KE_LOG_LEVEL_ERROR;
    sink.log = &countingSinkLog;

    const logger = ke_logger_create(null);
    defer logger.destroy.?(logger.ref);

    const result = logger.ref.*.add_sink.?(logger.ref, sink, null);
    try testing.expect(result);

    var ev = std.mem.zeroes(c.ke_log_event);
    ev.level = c.KE_LOG_LEVEL_INFO;
    ev.tag = "TEST";
    ev.message = "Message";

    logger.ref.*.log.?(logger.ref, &ev);

    try testing.expectEqual(@as(i32, 0), counter);
}

test "a sink with a null log fn is skipped" {
    var sink = std.mem.zeroes(c.ke_logger_sink);
    sink.min_level = c.KE_LOG_LEVEL_TRACE;
    sink.log = null;

    const logger = ke_logger_create(null);
    defer logger.destroy.?(logger.ref);

    const result = logger.ref.*.add_sink.?(logger.ref, sink, null);
    try testing.expect(result);

    var ev = std.mem.zeroes(c.ke_log_event);
    ev.level = c.KE_LOG_LEVEL_INFO;
    ev.tag = "TEST";
    ev.message = "Message";

    logger.ref.*.log.?(logger.ref, &ev);
}

fn expectConsoleSinkWrites(expected: []const u8, event: *const c.ke_log_event) !void {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeEvent(&writer, event);
    try testing.expectEqualStrings(expected, writer.buffered());
}

test "the console sink writes the level, tag and message of an event" {
    var ev = std.mem.zeroes(c.ke_log_event);
    ev.level = c.KE_LOG_LEVEL_INFO;
    ev.tag = "TEST";
    ev.message = "Message";

    try expectConsoleSinkWrites("[INFO] TEST: Message\n", &ev);
}

test "the console sink tolerates a null tag and message" {
    var ev = std.mem.zeroes(c.ke_log_event);
    ev.level = c.KE_LOG_LEVEL_INFO;
    ev.tag = null;
    ev.message = null;

    try expectConsoleSinkWrites("[INFO] : \n", &ev);
}

test "the console sink ignores an event it has no pointer to" {
    const sink = ke_console_sink_create();
    sink.log.?(null, null);
}

test "any number of sinks can be added and each receives the event" {
    const h = ke_logger_create(null);
    defer h.destroy.?(h.ref);
    var seen: u32 = 0;
    const counting = struct {
        fn log(sink: [*c]c.ke_logger_sink, _: [*c]const c.ke_log_event) callconv(.c) void {
            const n: *u32 = @ptrCast(@alignCast(sink.*.handle));
            n.* += 1;
        }
    };
    for (0..20) |_| {
        var sink = std.mem.zeroes(c.ke_logger_sink);
        sink.handle = &seen;
        sink.log = &counting.log;
        try testing.expect(h.ref.*.add_sink.?(h.ref, sink, null));
    }
    const event = c.ke_log_event{ .level = c.KE_LOG_LEVEL_INFO, .tag = "t", .message = "m" };
    h.ref.*.log.?(h.ref, &event);
    try testing.expectEqual(@as(u32, 20), seen);
}

test "destroy calls each sink destroy fn" {
    var counter: i32 = 0;

    var sink = std.mem.zeroes(c.ke_logger_sink);
    sink.handle = &counter;
    sink.min_level = c.KE_LOG_LEVEL_TRACE;
    sink.log = &consoleSinkLog;
    sink.destroy = &countingSinkDestroy;

    const logger = ke_logger_create(null);
    const result = logger.ref.*.add_sink.?(logger.ref, sink, null);
    try testing.expect(result);

    logger.destroy.?(logger.ref);

    try testing.expectEqual(@as(i32, 1), counter);
}

test "levelToString(KE_LOG_LEVEL_INFO) is INFO" {
    try testing.expectEqualStrings("INFO", std.mem.span(levelToString(c.KE_LOG_LEVEL_INFO)));
}

test "levelToString(-1) is UNKNOWN" {
    try testing.expectEqualStrings("UNKNOWN", std.mem.span(levelToString(-1)));
}

test "levelToString(6) is UNKNOWN" {
    try testing.expectEqualStrings("UNKNOWN", std.mem.span(levelToString(6)));
}

test "creating and destroying a logger leaves no block allocated" {
    const h = ke_logger_create(null);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}

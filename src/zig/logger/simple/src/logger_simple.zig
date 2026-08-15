const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const gpa = std.heap.c_allocator;

const c = @cImport({
    @cInclude("kernel_engine/logger/logger.h");
    @cInclude("kernel_engine/logger/log_level.h");
    @cInclude("stdio.h");
});

const E = @import("kerror").Errors(c);

const MAX_SINKS = 8;

const State = struct {
    sinks: [MAX_SINKS]c.ke_logger_sink,
    sink_count: c_int,
};

fn loggerDestroy(self: ?*c.ke_logger) callconv(.c) void {
    const logger = self orelse return;
    const s: *State = @ptrCast(@alignCast(logger.handle));
    var i: usize = 0;
    while (i < @as(usize, @intCast(s.sink_count))) : (i += 1) {
        if (s.sinks[i].destroy) |d| d(&s.sinks[i]);
    }
    gpa.destroy(s);
    gpa.destroy(logger);
}

fn loggerLog(self: ?*c.ke_logger, event: [*c]const c.ke_log_event) callconv(.c) void {
    if (self == null or event == null) return;
    const s: *State = @ptrCast(@alignCast(self.?.handle));
    var i: usize = 0;
    while (i < @as(usize, @intCast(s.sink_count))) : (i += 1) {
        const sink = &s.sinks[i];
        if (event.*.level >= sink.min_level) {
            if (sink.log) |log| log(sink, event);
        }
    }
}

fn loggerFlush(self: ?*c.ke_logger) callconv(.c) void {
    const logger = self orelse return;
    const s: *State = @ptrCast(@alignCast(logger.handle));
    var i: usize = 0;
    while (i < @as(usize, @intCast(s.sink_count))) : (i += 1) {
        if (s.sinks[i].flush) |f| f(&s.sinks[i]);
    }
}

fn loggerAddSink(self: ?*c.ke_logger, sink: c.ke_logger_sink, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const logger = self orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    const s: *State = @ptrCast(@alignCast(logger.handle));
    if (s.sink_count >= MAX_SINKS) {
        E.fail(out_error, .general, "sink capacity exceeded", @src());
        return false;
    }
    s.sinks[@intCast(s.sink_count)] = sink;
    s.sink_count += 1;
    return true;
}

fn consoleSinkLog(self: ?*c.ke_logger_sink, event: [*c]const c.ke_log_event) callconv(.c) void {
    _ = self;
    if (event == null) return;
    const label = ke_log_level_to_string(event.*.level);
    const tag: [*c]const u8 = if (event.*.tag != null) event.*.tag else "";
    const message: [*c]const u8 = if (event.*.message != null) event.*.message else "";
    _ = c.fprintf(c.stderr, "[%s] %s: %s\n", label, tag, message);
    _ = c.fflush(c.stderr);
}

fn consoleSinkFlush(self: ?*c.ke_logger_sink) callconv(.c) void {
    _ = self;
    _ = c.fflush(c.stderr);
}

fn consoleSinkDestroy(self: ?*c.ke_logger_sink) callconv(.c) void {
    _ = self;
}

export fn ke_console_sink_create() callconv(.c) c.ke_logger_sink {
    return .{
        .handle = null,
        .min_level = c.KE_LOG_LEVEL_TRACE,
        .log = &consoleSinkLog,
        .flush = &consoleSinkFlush,
        .destroy = &consoleSinkDestroy,
    };
}

export fn ke_log_level_to_string(level: i32) callconv(.c) [*c]const u8 {
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
    state.* = std.mem.zeroes(State);

    logger.handle = state;
    logger.log = &loggerLog;
    logger.flush = &loggerFlush;
    logger.add_sink = &loggerAddSink;

    return .{ .ref = logger, .destroy = &loggerDestroy };
}

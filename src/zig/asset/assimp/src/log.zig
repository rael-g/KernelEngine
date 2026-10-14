//! Reports the assimp loader's events to its logger and copies text into fixed-size name fields.

const std = @import("std");

const c = @import("c.zig").c;

const tag = "asset_loader";

/// The single place an event is built; every other function here reaches the logger through it.
fn emit(logger: ?*c.ke_logger, level: c_int, msg: [*:0]const u8) void {
    const lg = logger orelse return;
    var ev = c.ke_log_event{ .level = level, .tag = tag, .message = msg };
    if (lg.log) |f| f(lg, &ev);
}

/// Logs `msg` at information level.
pub fn info(logger: ?*c.ke_logger, msg: [*:0]const u8) void {
    emit(logger, c.KE_LOG_LEVEL_INFO, msg);
}

/// Logs `msg` at warning level.
pub fn warn(logger: ?*c.ke_logger, msg: [*:0]const u8) void {
    emit(logger, c.KE_LOG_LEVEL_WARNING, msg);
}

/// Logs at error level the context joined to the detail text of a failed Assimp call. A null
/// detail is written as a placeholder, and a joined text that does not fit its buffer is replaced
/// by a fixed message. Nothing is logged without a logger.
pub fn errCtx(logger: ?*c.ke_logger, context: []const u8, detail: [*c]const u8) void {
    if (logger == null) return;
    var buf: [1024]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{s}: {s}", .{
        context,
        if (detail != null) std.mem.span(detail) else "(no detail)",
    }) catch "asset loader error (detail too long to format)";
    emit(logger, c.KE_LOG_LEVEL_ERROR, text.ptr);
}

/// Copies a C string into a fixed buffer, cut to fit and always terminated. A null source leaves
/// an empty string, and a zero-length destination is left untouched.
pub fn copyString(dst: []u8, src: [*c]const u8) void {
    if (dst.len == 0) return;
    if (src == null) {
        dst[0] = 0;
        return;
    }
    const text = std.mem.span(src);
    const n = @min(text.len, dst.len - 1);
    @memcpy(dst[0..n], text[0..n]);
    dst[n] = 0;
}

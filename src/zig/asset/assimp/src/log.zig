// Logging helpers shared by the loader, converter and texture decoder. All are
// no-ops when the host supplied no logger.

const std = @import("std");

const c = @import("c.zig").c;

const tag = "asset_loader";

fn emit(logger: ?*c.ke_logger, level: c_int, msg: [*:0]const u8) void {
    const lg = logger orelse return;
    var ev = c.ke_log_event{ .level = level, .tag = tag, .message = msg };
    if (lg.log) |f| f(lg, &ev);
}

pub fn info(logger: ?*c.ke_logger, msg: [*:0]const u8) void {
    emit(logger, c.KE_LOG_LEVEL_INFO, msg);
}

pub fn warn(logger: ?*c.ke_logger, msg: [*:0]const u8) void {
    emit(logger, c.KE_LOG_LEVEL_WARNING, msg);
}

/// Logs "<context>: <detail>", the shape the loader uses to attach an assimp
/// error string to the operation that produced it.
pub fn errCtx(logger: ?*c.ke_logger, context: []const u8, detail: [*c]const u8) void {
    if (logger == null) return;
    var buf: [1024]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{s}: {s}", .{
        context,
        if (detail != null) std.mem.span(detail) else "(no detail)",
    }) catch "asset loader error (detail too long to format)";
    emit(logger, c.KE_LOG_LEVEL_ERROR, text.ptr);
}

/// Copies into a fixed-size C string field, truncating to fit and always
/// NUL-terminating.
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


const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("stdio.h");
});

const windows = struct {
    const SEM_FAILCRITICALERRORS: u32 = 0x0001;
    const SEM_NOGPFAULTERRORBOX: u32 = 0x0002;
    const SEM_NOOPENFILEERRORBOX: u32 = 0x8000;
    extern "kernel32" fn SetErrorMode(uMode: u32) callconv(.winapi) u32;
};

const names = @import("error_types.zig");

const slot_count = 2;
const message_max = 512;

export const KE_ERROR_GENERAL: c.ke_error_type = .{ .name = names.general, .parent = null };
export const KE_ERROR_NOT_FOUND: c.ke_error_type = .{ .name = names.not_found, .parent = null };
export const KE_ERROR_IO: c.ke_error_type = .{ .name = names.io, .parent = null };
export const KE_ERROR_OUT_OF_MEMORY: c.ke_error_type = .{ .name = names.out_of_memory, .parent = null };
export const KE_ERROR_INVALID_ARGUMENT: c.ke_error_type = .{ .name = names.invalid_argument, .parent = null };
export const KE_ERROR_NOT_INITIALIZED: c.ke_error_type = .{ .name = names.not_initialized, .parent = null };
export const KE_ERROR_NOT_SUPPORTED: c.ke_error_type = .{ .name = names.not_supported, .parent = null };
export const KE_ERROR_ALREADY_EXISTS: c.ke_error_type = .{ .name = names.already_exists, .parent = null };

export fn ke_error_is(err_in: ?*const c.ke_error, type_in: ?*const c.ke_error_type) callconv(.c) bool {
    const err = err_in orelse return false;
    const wanted = type_in orelse return false;
    var t: ?*const c.ke_error_type = @ptrCast(err.type);
    while (t) |node| {
        if (node == wanted) return true;
        t = @ptrCast(node.parent);
    }
    return false;
}

threadlocal var slots: [slot_count]c.ke_error = std.mem.zeroes([slot_count]c.ke_error);
threadlocal var messages: [slot_count][message_max]u8 = std.mem.zeroes([slot_count][message_max]u8);
threadlocal var next_slot: usize = 0;

export fn ke_error_set(
    out_error: [*c][*c]c.ke_error,
    err_type: ?*const c.ke_error_type,
    message: [*c]const u8,
    file: [*c]const u8,
    line: u32,
    cause: ?*const c.ke_error,
) callconv(.c) void {
    const slot = next_slot;
    next_slot = 1 - slot;

    const buf = &messages[slot];
    if (message != null) {
        const text = std.mem.span(message);
        const n = @min(text.len, buf.len - 1);
        @memcpy(buf[0..n], text[0..n]);
        buf[n] = 0;
    } else {
        buf[0] = 0;
    }

    const e = &slots[slot];
    e.* = .{
        .type = err_type,
        .message = @ptrCast(buf),
        .file = file,
        .line = line,
        .cause = cause,
    };
    if (out_error != null) out_error.* = e;
}

export fn ke_error_last() callconv(.c) ?*const c.ke_error {
    const last = 1 - next_slot;
    return if (slots[last].type != null) &slots[last] else null;
}

fn stderrFile() ?*c.FILE {
    if (@import("builtin").os.tag == .windows) return c.__acrt_iob_func(2);
    return c.stderr;
}

export fn ke_error_fatal(err_in: ?*const c.ke_error) callconv(.c) noreturn {
    if (@import("builtin").os.tag == .windows) {
        _ = windows.SetErrorMode(windows.SEM_FAILCRITICALERRORS |
            windows.SEM_NOGPFAULTERRORBOX |
            windows.SEM_NOOPENFILEERRORBOX);
    }

    const err = stderrFile();
    _ = c.fputs("FATAL: ", err);
    if (err_in) |first| {
        var buf: [1024]u8 = undefined;
        var e: ?*const c.ke_error = first;
        while (e) |node| {
            const text = std.fmt.bufPrintZ(&buf, "[{s}] {s} ({s}:{d})", .{
                if (node.type != null) spanOr(node.type.*.name, "?") else "?",
                spanOr(node.message, "(no message)"),
                spanOr(node.file, "?"),
                node.line,
            }) catch "[?] (error detail too long to format)";
            _ = c.fputs(text.ptr, err);
            e = node.cause;
            if (e != null) _ = c.fputs("\n  caused by: ", err);
        }
        _ = c.fputs("\n", err);
    } else {
        _ = c.fputs("no error context provided\n", err);
    }
    _ = c.fflush(err);

    std.process.exit(1);
}

fn spanOr(s: [*c]const u8, fallback: []const u8) []const u8 {
    return if (s != null) std.mem.span(s) else fallback;
}

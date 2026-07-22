// ke_common — the engine's error vocabulary: the generic type singletons, the
// thread-local slot a failing callee fills, and the fatal path.
//
// Nothing here allocates. Everything an error needs lives in static storage:
// the type singletons are constants and the slots are a thread-local ring. An
// error that has to outlive the call producing it is built as a program-lifetime
// constant by the code that raises it, not copied onto a heap.

const std = @import("std");

// This .so is dlopen'd by a foreign, non-Zig host alongside many sibling
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack exceeds glibc's small static-TLS surplus once enough plugins
// accumulate, aborting with "cannot allocate memory in static TLS block".
pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    // The fatal path reports through libc rather than Zig's std IO: it must
    // work when everything else is already broken, and it is the one place the
    // evolving std writer API buys nothing over fputs.
    @cInclude("stdio.h");
});

/// Suppresses the GPF/Watson, missing-DLL and file-open dialogs so the process
/// can die quietly after printing. Declared here rather than pulled from std so
/// the symbol this depends on is explicit and stable.
const windows = struct {
    const SEM_FAILCRITICALERRORS: u32 = 0x0001;
    const SEM_NOGPFAULTERRORBOX: u32 = 0x0002;
    const SEM_NOOPENFILEERRORBOX: u32 = 0x8000;
    extern "kernel32" fn SetErrorMode(uMode: u32) callconv(.winapi) u32;
};

const names = @import("error_types.zig");

/// Depth-2 ring: two slots, so wrapping an error (KE_ERROR_WRAP) keeps the inner
/// error pointer valid while the outer one is being built.
const slot_count = 2;
/// Longest error message retained; anything past this is truncated, never
/// allocated — a failing path must not depend on the allocator to report itself.
const message_max = 512;

// -- generic type singletons -------------------------------------------------
//
// Exported as data symbols, so `&KE_ERROR_NOT_FOUND` from C keeps working. The
// names come from the shared list the Zig error seam also reads: callers match
// by name, and the two sets of instances must agree byte for byte.

export const KE_ERROR_GENERAL: c.ke_error_type = .{ .name = names.general, .parent = null };
export const KE_ERROR_NOT_FOUND: c.ke_error_type = .{ .name = names.not_found, .parent = null };
export const KE_ERROR_IO: c.ke_error_type = .{ .name = names.io, .parent = null };
export const KE_ERROR_OUT_OF_MEMORY: c.ke_error_type = .{ .name = names.out_of_memory, .parent = null };
export const KE_ERROR_INVALID_ARGUMENT: c.ke_error_type = .{ .name = names.invalid_argument, .parent = null };
export const KE_ERROR_NOT_INITIALIZED: c.ke_error_type = .{ .name = names.not_initialized, .parent = null };
export const KE_ERROR_NOT_SUPPORTED: c.ke_error_type = .{ .name = names.not_supported, .parent = null };
export const KE_ERROR_ALREADY_EXISTS: c.ke_error_type = .{ .name = names.already_exists, .parent = null };

// -- type matching -----------------------------------------------------------

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

// -- thread-local slots ------------------------------------------------------

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
    // next_slot already advanced past the last write; the filled one is the other.
    const last = 1 - next_slot;
    return if (slots[last].type != null) &slots[last] else null;
}

// -- fatal -------------------------------------------------------------------

/// Prints the whole error chain to stderr and ends the process without going
/// through abort(): no OS crash dialog, and the message is always readable
/// first. The engine's only sanctioned give-up path.
export fn ke_error_fatal(err_in: ?*const c.ke_error) callconv(.c) noreturn {
    if (@import("builtin").os.tag == .windows) {
        _ = windows.SetErrorMode(windows.SEM_FAILCRITICALERRORS |
            windows.SEM_NOGPFAULTERRORBOX |
            windows.SEM_NOOPENFILEERRORBOX);
    }

    _ = c.fputs("FATAL: ", c.stderr);
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
            _ = c.fputs(text.ptr, c.stderr);
            e = node.cause;
            if (e != null) _ = c.fputs("\n  caused by: ", c.stderr);
        }
        _ = c.fputs("\n", c.stderr);
    } else {
        _ = c.fputs("no error context provided\n", c.stderr);
    }
    _ = c.fflush(c.stderr);

    std.process.exit(1);
}

fn spanOr(s: [*c]const u8, fallback: []const u8) []const u8 {
    return if (s != null) std.mem.span(s) else fallback;
}

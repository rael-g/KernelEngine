//! Per-thread error recording for one translated C namespace. `Errors` takes the namespace that
//! declares the error record and its type, and returns the functions that fill an error and the
//! one that ends the process on it. The result owns one error record and one text buffer per
//! thread, so the error a failing call hands out points at storage of the calling thread, and the
//! next failure on that thread overwrites it.
//!
//! `fail` takes the type of the error from `Kind`, which selects among the singleton types
//! `typeOf` returns, and `failWithType` takes a type from its caller. Both copy the message, cut
//! to the buffer, record the file and line of the failing call, set no cause, and point the
//! caller's error output at the record when it is not null. `fatal` writes the chain of an error
//! to standard error, following its causes, and exits with a failure status.
//!
//! The file also declares `_DllMainCRTStartup`, the mingw DLL entry point, so that a plugin root
//! can re-export it and have the static initializers of its linked C and C++ code run.

const std = @import("std");

const names = @import("src/error_types.zig");

const io = @cImport({
    @cInclude("stdio.h");
});

const windows = struct {
    const SEM_FAILCRITICALERRORS: u32 = 0x0001;
    const SEM_NOGPFAULTERRORBOX: u32 = 0x0002;
    const SEM_NOOPENFILEERRORBOX: u32 = 0x8000;
    extern "kernel32" fn SetErrorMode(uMode: u32) callconv(.winapi) u32;
};

/// The mingw DLL entry point, declared so that a plugin root can re-export it. Zig's own DLL entry
/// point does not run the static initializers of linked C and C++ libraries; the re-export is what
/// makes them run.
pub extern fn _DllMainCRTStartup(
    hinst: std.os.windows.HINSTANCE,
    reason: std.os.windows.DWORD,
    reserved: std.os.windows.LPVOID,
) callconv(.winapi) std.os.windows.BOOL;

fn stderrFile() [*c]io.FILE {
    if (@import("builtin").os.tag == .windows) return io.__acrt_iob_func(2);
    return io.stderr;
}

pub fn Errors(comptime c: type) type {
    return struct {
        /// The kinds of singleton error type that `typeOf` returns. Each value indexes `types`,
        /// which has one entry per name in `names.generic`, so the kinds pair with those names by
        /// position.
        pub const Kind = enum {
            general,
            not_found,
            io,
            out_of_memory,
            invalid_argument,
            not_initialized,
            not_supported,
            already_exists,
        };

        const types = blk: {
            var t: [names.generic.len]c.ke_error_type = undefined;
            for (names.generic, 0..) |n, i| t[i] = .{ .name = n, .parent = null };
            break :blk t;
        };

        /// Returns the same address for a kind on every call. The entries are fixed at compile
        /// time, so the pointer stays valid for the life of the program.
        pub fn typeOf(kind: Kind) *const c.ke_error_type {
            return &types[@intFromEnum(kind)];
        }

        const message_max = 512;
        /// The error record that `fail` and `failWithType` fill, one per thread.
        threadlocal var slot: c.ke_error = undefined;
        /// The text buffer behind the message of `slot`, one per thread.
        threadlocal var message: [message_max]u8 = undefined;

        /// Returns a pointer into the thread's message buffer, which the next failure on that
        /// thread overwrites. A null message returns null.
        fn own(msg: [*c]const u8) [*c]const u8 {
            if (msg == null) return null;
            const text = std.mem.span(msg);
            const n = @min(text.len, message_max - 1);
            std.mem.copyForwards(u8, message[0..n], text[0..n]);
            message[n] = 0;
            return &message;
        }

        /// Records a failure of the given kind in the calling thread's error slot. When the
        /// out-parameter is not null, it is set to point at that slot.
        pub fn fail(out_error: [*c][*c]c.ke_error, kind: Kind, msg: [*c]const u8, src: std.builtin.SourceLocation) void {
            slot = .{
                .type = &types[@intFromEnum(kind)],
                .message = own(msg),
                .file = src.file,
                .line = @intCast(src.line),
                .cause = null,
            };
            if (out_error != null) out_error.* = &slot;
        }

        /// Like `fail`, but the error type is the one passed in, and it is stored by pointer, so it
        /// must outlive the error.
        pub fn failWithType(out_error: [*c][*c]c.ke_error, error_type: *const c.ke_error_type,
                            msg: [*c]const u8, src: std.builtin.SourceLocation) void {
            slot = .{
                .type = error_type,
                .message = own(msg),
                .file = src.file,
                .line = @intCast(src.line),
                .cause = null,
            };
            if (out_error != null) out_error.* = &slot;
        }

        /// Writes the error chain to standard error and ends the process with a failure status,
        /// so no defer of the caller runs. Only standard error is flushed.
        pub fn fatal(err_in: ?*const c.ke_error) noreturn {
            if (@import("builtin").os.tag == .windows) {
                _ = windows.SetErrorMode(windows.SEM_FAILCRITICALERRORS |
                    windows.SEM_NOGPFAULTERRORBOX |
                    windows.SEM_NOOPENFILEERRORBOX);
            }

            const err = stderrFile();
            _ = io.fputs("FATAL: ", err);
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
                    _ = io.fputs(text.ptr, err);
                    e = node.cause;
                    if (e != null) _ = io.fputs("\n  caused by: ", err);
                }
                _ = io.fputs("\n", err);
            } else {
                _ = io.fputs("no error context provided\n", err);
            }
            _ = io.fflush(err);

            std.process.exit(1);
        }
    };
}

fn spanOr(s: [*c]const u8, fallback: []const u8) []const u8 {
    return if (s != null) std.mem.span(s) else fallback;
}

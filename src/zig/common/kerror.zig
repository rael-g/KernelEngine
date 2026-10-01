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

/// Workaround for a Zig defect on `x86_64-windows-gnu`. Re-export from the root
/// module of any plugin that links C or C++ static libraries:
///
/// pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;
///
/// Do not hand-roll a `DllMain` instead.
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

        /// The program-lifetime singleton for `kind`.
        pub fn typeOf(kind: Kind) *const c.ke_error_type {
            return &types[@intFromEnum(kind)];
        }

        const message_max = 512;
        threadlocal var slot: c.ke_error = undefined;
        threadlocal var message: [message_max]u8 = undefined;

        fn own(msg: [*c]const u8) [*c]const u8 {
            if (msg == null) return null;
            const text = std.mem.span(msg);
            const n = @min(text.len, message_max - 1);
            std.mem.copyForwards(u8, message[0..n], text[0..n]);
            message[n] = 0;
            return &message;
        }

        /// Fill the C error ABI at an exported boundary: point *out_error (when
        /// non-null) at a thread-local ke_error describing `kind` with `msg`,
        /// tagged with the caller's source location. Pass @src() from the export.
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

        /// Raise an error whose type was decided elsewhere, here on the calling
        /// thread. The message describes where the failure was picked up, not what
        /// went wrong.
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

        /// Prints the error chain to stderr and ends the process, with no OS crash
        /// dialog. Mirrors ke_common's ke_error_fatal.
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

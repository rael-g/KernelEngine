//! The Zig face of the engine's error record: each call lands in `ke_error_set` of ke_common, so
//! every plugin shares one per-thread record and one set of error types. Also declares the mingw
//! DLL entry point a plugin root re-exports.

const std = @import("std");

/// The mingw DLL entry point, declared so that a plugin root can re-export it. Zig's own DLL entry
/// point does not run the static initializers of linked C and C++ libraries; the re-export is what
/// makes them run.
pub extern fn _DllMainCRTStartup(
    hinst: std.os.windows.HINSTANCE,
    reason: std.os.windows.DWORD,
    reserved: std.os.windows.LPVOID,
) callconv(.winapi) std.os.windows.BOOL;

/// Returns the error functions for the contract types of `c`, the cimport it is given, which must
/// include `kernel_engine/common/error.h`. A failure is recorded by `ke_error_set`, so the record it
/// hands out is valid until two more failures on the same thread.
pub fn Errors(comptime c: type) type {
    return struct {
        /// The generic error types, in the order of the names in `src/error_types.zig`.
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

        /// Returns ke_common's singleton for the kind.
        pub fn typeOf(kind: Kind) *const c.ke_error_type {
            return switch (kind) {
                .general => &c.KE_ERROR_GENERAL,
                .not_found => &c.KE_ERROR_NOT_FOUND,
                .io => &c.KE_ERROR_IO,
                .out_of_memory => &c.KE_ERROR_OUT_OF_MEMORY,
                .invalid_argument => &c.KE_ERROR_INVALID_ARGUMENT,
                .not_initialized => &c.KE_ERROR_NOT_INITIALIZED,
                .not_supported => &c.KE_ERROR_NOT_SUPPORTED,
                .already_exists => &c.KE_ERROR_ALREADY_EXISTS,
            };
        }

        /// Records a failure of the given kind and, when the out-parameter is not null, points it at
        /// the record. The message is copied.
        pub fn fail(out_error: [*c][*c]c.ke_error, kind: Kind, msg: [*c]const u8, src: std.builtin.SourceLocation) void {
            c.ke_error_set(out_error, typeOf(kind), msg, src.file, @intCast(src.line), null);
        }

        /// Like `fail`, with an error type of the caller's, which must outlive the error.
        pub fn failWithType(out_error: [*c][*c]c.ke_error, error_type: *const c.ke_error_type,
                            msg: [*c]const u8, src: std.builtin.SourceLocation) void {
            c.ke_error_set(out_error, error_type, msg, src.file, @intCast(src.line), null);
        }

        /// Like `fail`, chaining `cause` as the error that led to this one.
        pub fn wrap(out_error: [*c][*c]c.ke_error, kind: Kind, msg: [*c]const u8, cause: ?*const c.ke_error,
                    src: std.builtin.SourceLocation) void {
            c.ke_error_set(out_error, typeOf(kind), msg, src.file, @intCast(src.line), cause);
        }

        /// Records a failure of the kind result code `code` names, for a caller that reports through
        /// `ke_error` a call that returned `ke_result`; a code of no general kind is `general`.
        /// `c` must include `kernel_engine/result/result.h`. A bridge while both shapes coexist.
        pub fn failCode(out_error: [*c][*c]c.ke_error, code: c.ke_result, msg: [*c]const u8, src: std.builtin.SourceLocation) void {
            const pairs = .{
                .{ c.KE_RESULT_NOT_FOUND, Kind.not_found },
                .{ c.KE_RESULT_IO, Kind.io },
                .{ c.KE_RESULT_OUT_OF_MEMORY, Kind.out_of_memory },
                .{ c.KE_RESULT_INVALID_ARGUMENT, Kind.invalid_argument },
                .{ c.KE_RESULT_NOT_INITIALIZED, Kind.not_initialized },
                .{ c.KE_RESULT_NOT_SUPPORTED, Kind.not_supported },
                .{ c.KE_RESULT_ALREADY_EXISTS, Kind.already_exists },
            };
            inline for (pairs) |pair| {
                if (code == pair[0]) return fail(out_error, pair[1], msg, src);
            }
            fail(out_error, .general, msg, src);
        }

        /// The result code of the general kind `err` is of, walking its type's parents; a null
        /// error or a type of no general kind is `KE_RESULT_GENERAL`. `c` must include
        /// `kernel_engine/result/result.h`. A bridge while both shapes coexist.
        pub fn codeOf(err: [*c]const c.ke_error) c.ke_result {
            const pairs = .{
                .{ c.KE_RESULT_NOT_FOUND, Kind.not_found },
                .{ c.KE_RESULT_IO, Kind.io },
                .{ c.KE_RESULT_OUT_OF_MEMORY, Kind.out_of_memory },
                .{ c.KE_RESULT_INVALID_ARGUMENT, Kind.invalid_argument },
                .{ c.KE_RESULT_NOT_INITIALIZED, Kind.not_initialized },
                .{ c.KE_RESULT_NOT_SUPPORTED, Kind.not_supported },
                .{ c.KE_RESULT_ALREADY_EXISTS, Kind.already_exists },
            };
            if (err != null) {
                inline for (pairs) |pair| {
                    if (c.ke_error_is(err, typeOf(pair[1]))) return @intCast(pair[0]);
                }
            }
            return @intCast(c.KE_RESULT_GENERAL);
        }

        /// Writes the error chain to standard error and ends the process with a failure status.
        pub fn fatal(err: ?*const c.ke_error) noreturn {
            c.ke_error_fatal(err);
        }
    };
}

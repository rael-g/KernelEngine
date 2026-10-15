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

        /// Writes the error chain to standard error and ends the process with a failure status.
        pub fn fatal(err: ?*const c.ke_error) noreturn {
            c.ke_error_fatal(err);
        }
    };
}

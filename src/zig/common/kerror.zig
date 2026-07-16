const std = @import("std");

// Zig-native error utility for the C-ABI seam. Migrated Zig plugins use Zig's
// own error handling internally (error unions, errdefer, try) and call fail()
// only at an exported boundary to translate into the rich ke_error ABI a C/C#
// caller expects — WITHOUT linking ke_common. Zig owns its own error-type
// singletons and thread-local slot here; ke_common's ke_error_set stays the
// C-side utility. Cross-boundary matching is by type name, not pointer identity
// (Zig's singletons are distinct instances from ke_common's).
//
// The consuming plugin only needs the ke_error / ke_error_type struct layout,
// pulled from <kernel_engine/common/error.h> via @cImport — a header include,
// never a link. `c` is the plugin's own @cImport, passed in so this module
// shares its exact ke_error type.

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

        // Program-lifetime type singletons, one per kind. Names mirror
        // ke_common's KE_ERROR_* so a name-based match still works across the
        // boundary. parent is null (the generic roots have no parent).
        const types = blk: {
            var t: [8]c.ke_error_type = undefined;
            t[@intFromEnum(Kind.general)] = .{ .name = "ke.general", .parent = null };
            t[@intFromEnum(Kind.not_found)] = .{ .name = "ke.not_found", .parent = null };
            t[@intFromEnum(Kind.io)] = .{ .name = "ke.io", .parent = null };
            t[@intFromEnum(Kind.out_of_memory)] = .{ .name = "ke.out_of_memory", .parent = null };
            t[@intFromEnum(Kind.invalid_argument)] = .{ .name = "ke.invalid_argument", .parent = null };
            t[@intFromEnum(Kind.not_initialized)] = .{ .name = "ke.not_initialized", .parent = null };
            t[@intFromEnum(Kind.not_supported)] = .{ .name = "ke.not_supported", .parent = null };
            t[@intFromEnum(Kind.already_exists)] = .{ .name = "ke.already_exists", .parent = null };
            break :blk t;
        };

        // Thread-local slot the written ke_error* points into. Valid until the
        // next fail() on this thread — same contract as ke_common's ring buffer.
        threadlocal var slot: c.ke_error = undefined;

        /// Fill the C error ABI at an exported boundary: point *out_error (when
        /// non-null) at a thread-local ke_error describing `kind` with `msg`,
        /// tagged with the caller's source location. Pass @src() from the export.
        pub fn fail(out_error: [*c][*c]c.ke_error, kind: Kind, msg: [*c]const u8, src: std.builtin.SourceLocation) void {
            slot = .{
                .type = &types[@intFromEnum(kind)],
                .message = msg,
                .file = src.file,
                .line = @intCast(src.line),
                .cause = null,
            };
            if (out_error != null) out_error.* = &slot;
        }
    };
}

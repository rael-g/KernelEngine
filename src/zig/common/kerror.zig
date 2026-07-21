const std = @import("std");

const names = @import("src/error_types.zig");

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

        // Program-lifetime type singletons, one per kind. Matching across the
        // boundary is by NAME (a C# caller does err.Is("ke.error.not_found"),
        // and Zig's singletons are distinct instances from ke_common's), so the
        // strings come from the shared list both sides read — they cannot drift.
        // parent is null — the generic roots have no parent.
        const types = blk: {
            var t: [names.generic.len]c.ke_error_type = undefined;
            for (names.generic, 0..) |n, i| t[i] = .{ .name = n, .parent = null };
            break :blk t;
        };

        /// The program-lifetime singleton for `kind`. Needed where an error must
        /// outlive the call that produced it — an async completion runs after
        /// its originating frame is gone, so it cannot point at the thread-local
        /// slot below. Referencing ke_common's exported singletons instead would
        /// force a link against it, which this seam exists to avoid.
        pub fn typeOf(kind: Kind) *const c.ke_error_type {
            return &types[@intFromEnum(kind)];
        }

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

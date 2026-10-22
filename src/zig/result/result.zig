//! The Zig side of `ke_result`: the error set a plugin fails with through `try`, and the
//! conversions between it and the code at the ABI edge.

const std = @import("std");

/// The error set and conversions for `c`, the C import of a plugin, which must include
/// `kernel_engine/result/result.h`. `domain` pairs each error of the plugin's domain with the code
/// its header declares for it, as `.{ .{ error.ShaderCompilation, c.KE_RESULT_RENDER_SHADER_COMPILATION } }`.
/// A general code of the header with no error here fails the build.
pub fn Result(comptime c: type, comptime domain: anytype) type {
    const general = .{
        .{ error.General, c.KE_RESULT_GENERAL },
        .{ error.NotFound, c.KE_RESULT_NOT_FOUND },
        .{ error.Io, c.KE_RESULT_IO },
        .{ error.OutOfMemory, c.KE_RESULT_OUT_OF_MEMORY },
        .{ error.InvalidArgument, c.KE_RESULT_INVALID_ARGUMENT },
        .{ error.NotInitialized, c.KE_RESULT_NOT_INITIALIZED },
        .{ error.NotSupported, c.KE_RESULT_NOT_SUPPORTED },
        .{ error.AlreadyExists, c.KE_RESULT_ALREADY_EXISTS },
    };
    const pairs = general ++ domain;

    comptime {
        @setEvalBranchQuota(100_000);
        for (@typeInfo(c).@"struct".decls) |decl| {
            if (!std.mem.startsWith(u8, decl.name, "KE_RESULT_") or std.mem.startsWith(u8, decl.name, "KE_RESULT_DOMAIN_")) continue;
            const value = @field(c, decl.name);
            if (@TypeOf(value) != c_int and @TypeOf(value) != c_uint) continue;
            if (value == c.KE_RESULT_MAX_ENUM or value >> 16 != 0) continue;
            for (pairs) |pair| {
                if (pair[1] == value) break;
            } else @compileError(decl.name ++ " has no error in the Zig error set of ke_result");
        }
    }

    return struct {
        /// The errors a call of the plugin fails with: the general ones and those of its domain.
        pub const Error = blk: {
            var set = error{};
            for (pairs) |pair| set = set || @TypeOf(pair[0]);
            break :blk set;
        };

        /// The code of `err`; an error the set does not name is `KE_RESULT_GENERAL`.
        pub fn code(err: anyerror) c.ke_result {
            inline for (pairs) |pair| {
                if (err == pair[0]) return @intCast(pair[1]);
            }
            return @intCast(c.KE_RESULT_GENERAL);
        }

        /// The code a call that returned `result` hands across the ABI.
        pub fn of(result: anyerror!void) c.ke_result {
            result catch |err| return code(err);
            return @intCast(c.KE_OK);
        }

        /// The error of a code a C call returned, for a caller that goes on with `try`; a code the
        /// set does not name is `error.General`.
        pub fn check(result: c.ke_result) Error!void {
            if (result == c.KE_OK) return;
            inline for (pairs) |pair| {
                if (result == pair[1]) return pair[0];
            }
            return error.General;
        }
    };
}

const testing = std.testing;
const test_c = @import("c");
const R = Result(test_c, .{.{ error.ProbeOwnCode, test_c.KE_RESULT_CODE(test_c.KE_RESULT_DOMAIN_LOGGER, 1) }});

test "a Zig error crosses the ABI as the code of the same name and comes back as the same error" {
    try testing.expectEqual(@as(test_c.ke_result, @intCast(test_c.KE_RESULT_NOT_FOUND)), R.code(error.NotFound));
    try testing.expectError(error.NotFound, R.check(@intCast(test_c.KE_RESULT_NOT_FOUND)));
}

test "a domain's own error crosses the ABI as the code its header declares" {
    const own: test_c.ke_result = @intCast(test_c.KE_RESULT_CODE(test_c.KE_RESULT_DOMAIN_LOGGER, 1));
    try testing.expectEqual(own, R.code(error.ProbeOwnCode));
    try testing.expectError(error.ProbeOwnCode, R.check(own));
}

test "an error the set does not name crosses the ABI as the general code" {
    try testing.expectEqual(@as(test_c.ke_result, @intCast(test_c.KE_RESULT_GENERAL)), R.code(error.SomethingElse));
}

test "a code the set does not name comes back as the general error" {
    try testing.expectError(error.General, R.check(@intCast(test_c.KE_RESULT_CODE(test_c.KE_RESULT_DOMAIN_WINDOW, 9))));
}

test "a call that succeeded crosses the ABI as KE_OK and checks as success" {
    try testing.expectEqual(@as(test_c.ke_result, @intCast(test_c.KE_OK)), R.of({}));
    try R.check(@intCast(test_c.KE_OK));
}

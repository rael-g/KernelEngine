const std = @import("std");
const abi = @import("abi");
const c = @import("c");

fn expectSameLayout(comptime A: type, comptime C: type) !void {
    @setEvalBranchQuota(100_000_000);
    if (@typeInfo(C) == .@"opaque") return;
    try std.testing.expectEqual(@sizeOf(C), @sizeOf(A));
    try std.testing.expectEqual(@alignOf(C), @alignOf(A));
    switch (@typeInfo(A)) {
        .@"struct" => |s| inline for (s.fields) |f| {
            try std.testing.expectEqual(@offsetOf(C, f.name), @offsetOf(A, f.name));
            try expectSameLayout(f.type, @FieldType(C, f.name));
        },
        .@"union" => |u| inline for (u.fields) |f| try expectSameLayout(f.type, @FieldType(C, f.name)),
        else => {},
    }
}

fn translated(comptime name: []const u8) type {
    return if (@hasDecl(c, name)) @field(c, name) else @field(c, "struct_" ++ name);
}

test "every record is laid out as the header lays it out" {
    @setEvalBranchQuota(100_000_000);
    try expectSameLayout(abi.c.ke_job_ctx, translated("ke_job_ctx"));
    try expectSameLayout(abi.c.ke_job_system, translated("ke_job_system"));
    try expectSameLayout(abi.c.ke_job_system_handle, translated("ke_job_system_handle"));
    if (@hasDecl(c, "ke_job_fn")) try expectSameLayout(abi.c.ke_job_fn, c.ke_job_fn);
    if (@hasDecl(c, "ke_job_range_fn")) try expectSameLayout(abi.c.ke_job_range_fn, c.ke_job_range_fn);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqualStrings(c.KE_JOB_SYSTEM_SETTING_WORKER_COUNT, abi.c.KE_JOB_SYSTEM_SETTING_WORKER_COUNT);
}

extern const layout_values: [13]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_job_ctx),
        @offsetOf(abi.c.ke_job_ctx, "dep_results"),
        @offsetOf(abi.c.ke_job_ctx, "dep_count"),
        @sizeOf(abi.c.ke_job_system),
        @offsetOf(abi.c.ke_job_system, "handle"),
        @offsetOf(abi.c.ke_job_system, "dispatch"),
        @offsetOf(abi.c.ke_job_system, "parallel_for"),
        @offsetOf(abi.c.ke_job_system, "worker_slots"),
        @offsetOf(abi.c.ke_job_system, "drain"),
        @sizeOf(abi.c.ke_job_system_handle),
        @offsetOf(abi.c.ke_job_system_handle, "ref"),
        @offsetOf(abi.c.ke_job_system_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

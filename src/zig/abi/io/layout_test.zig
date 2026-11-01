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
    try expectSameLayout(abi.c.ke_io_dir_entry, translated("ke_io_dir_entry"));
    try expectSameLayout(abi.c.ke_io_result, translated("ke_io_result"));
    try expectSameLayout(abi.c.ke_io, translated("ke_io"));
    try expectSameLayout(abi.c.ke_io_handle, translated("ke_io_handle"));
}

extern const layout_values: [33]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_io_dir_entry),
        @offsetOf(abi.c.ke_io_dir_entry, "name"),
        @offsetOf(abi.c.ke_io_dir_entry, "kind"),
        @sizeOf(abi.c.ke_io_result),
        @offsetOf(abi.c.ke_io_result, "file"),
        @offsetOf(abi.c.ke_io_result, "bytes"),
        @offsetOf(abi.c.ke_io_result, "size"),
        @offsetOf(abi.c.ke_io_result, "stat"),
        @offsetOf(abi.c.ke_io_result, "exists"),
        @offsetOf(abi.c.ke_io_result, "entries"),
        @offsetOf(abi.c.ke_io_result, "entry_count"),
        @sizeOf(abi.c.ke_io),
        @offsetOf(abi.c.ke_io, "handle"),
        @offsetOf(abi.c.ke_io, "read_file"),
        @offsetOf(abi.c.ke_io, "open"),
        @offsetOf(abi.c.ke_io, "read_at"),
        @offsetOf(abi.c.ke_io, "stat"),
        @offsetOf(abi.c.ke_io, "file_exists"),
        @offsetOf(abi.c.ke_io, "dir_exists"),
        @offsetOf(abi.c.ke_io, "list_dir"),
        @offsetOf(abi.c.ke_io, "write_file"),
        @offsetOf(abi.c.ke_io, "make_dir"),
        @offsetOf(abi.c.ke_io, "remove"),
        @offsetOf(abi.c.ke_io, "rename"),
        @offsetOf(abi.c.ke_io, "is_completed"),
        @offsetOf(abi.c.ke_io, "wait"),
        @offsetOf(abi.c.ke_io, "close"),
        @offsetOf(abi.c.ke_io, "free_bytes"),
        @offsetOf(abi.c.ke_io, "free_entries"),
        @sizeOf(abi.c.ke_io_handle),
        @offsetOf(abi.c.ke_io_handle, "ref"),
        @offsetOf(abi.c.ke_io_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

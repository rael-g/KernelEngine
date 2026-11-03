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
    try expectSameLayout(abi.c.ke_mesh_handle, translated("ke_mesh_handle"));
    try expectSameLayout(abi.c.ke_texture_handle, translated("ke_texture_handle"));
    try expectSameLayout(abi.c.ke_material_handle, translated("ke_material_handle"));
    try expectSameLayout(abi.c.ke_cubemap_handle, translated("ke_cubemap_handle"));
    try expectSameLayout(abi.c.ke_shadow_map_handle, translated("ke_shadow_map_handle"));
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_ALPHA_MODE_OPAQUE), @as(i64, abi.c.KE_ALPHA_MODE_OPAQUE));
    try std.testing.expectEqual(@as(i64, c.KE_ALPHA_MODE_MASK), @as(i64, abi.c.KE_ALPHA_MODE_MASK));
    try std.testing.expectEqual(@as(i64, c.KE_ALPHA_MODE_BLEND), @as(i64, abi.c.KE_ALPHA_MODE_BLEND));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_HANDLE_INDEX_BITS), @as(i128, abi.c.KE_HANDLE_INDEX_BITS));
    try std.testing.expectEqual(@as(i128, c.KE_HANDLE_GENERATION_BITS), @as(i128, abi.c.KE_HANDLE_GENERATION_BITS));
    try std.testing.expectEqual(@as(i128, c.KE_HANDLE_INDEX_MASK), @as(i128, abi.c.KE_HANDLE_INDEX_MASK));
    try std.testing.expectEqual(@as(i128, c.KE_HANDLE_GENERATION_MASK), @as(i128, abi.c.KE_HANDLE_GENERATION_MASK));
    try std.testing.expectEqual(@as(i128, c.KE_HANDLE_GENERATION_FIRST), @as(i128, abi.c.KE_HANDLE_GENERATION_FIRST));
    try std.testing.expectEqual(@as(i128, c.KE_HANDLE_NONE), @as(i128, abi.c.KE_HANDLE_NONE));
    try std.testing.expectEqual(std.mem.toBytes(c.KE_MESH_NONE), std.mem.toBytes(abi.c.KE_MESH_NONE));
    try std.testing.expectEqual(std.mem.toBytes(c.KE_TEXTURE_NONE), std.mem.toBytes(abi.c.KE_TEXTURE_NONE));
    try std.testing.expectEqual(std.mem.toBytes(c.KE_MATERIAL_NONE), std.mem.toBytes(abi.c.KE_MATERIAL_NONE));
    try std.testing.expectEqual(std.mem.toBytes(c.KE_CUBEMAP_NONE), std.mem.toBytes(abi.c.KE_CUBEMAP_NONE));
    try std.testing.expectEqual(std.mem.toBytes(c.KE_SHADOW_MAP_NONE), std.mem.toBytes(abi.c.KE_SHADOW_MAP_NONE));
}

extern const layout_values: [11]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_mesh_handle),
        @offsetOf(abi.c.ke_mesh_handle, "bits"),
        @sizeOf(abi.c.ke_texture_handle),
        @offsetOf(abi.c.ke_texture_handle, "bits"),
        @sizeOf(abi.c.ke_material_handle),
        @offsetOf(abi.c.ke_material_handle, "bits"),
        @sizeOf(abi.c.ke_cubemap_handle),
        @offsetOf(abi.c.ke_cubemap_handle, "bits"),
        @sizeOf(abi.c.ke_shadow_map_handle),
        @offsetOf(abi.c.ke_shadow_map_handle, "bits"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

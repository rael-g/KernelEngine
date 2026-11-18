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
    try expectSameLayout(abi.c.ke_extraction, translated("ke_extraction"));
    try expectSameLayout(abi.c.ke_extraction_handle, translated("ke_extraction_handle"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_extraction_custom_fn")) try expectSameLayout(abi.c.ke_extraction_custom_fn, c.ke_extraction_custom_fn);
    if (@hasDecl(c, "ke_extraction_interpolate_fn")) try expectSameLayout(abi.c.ke_extraction_interpolate_fn, c.ke_extraction_interpolate_fn);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_removal_tracker")) try expectSameLayout(abi.c.ke_removal_tracker, c.ke_removal_tracker);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_RENDER_SYNCED, abi.c.KE_COMPONENT_NAME_RENDER_SYNCED);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_INTERPOLATED, abi.c.KE_COMPONENT_NAME_INTERPOLATED);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_TELEPORTED, abi.c.KE_COMPONENT_NAME_TELEPORTED);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_FRAME_LOCAL, abi.c.KE_COMPONENT_NAME_FRAME_LOCAL);
}

extern const layout_values: [14]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_extraction),
        @offsetOf(abi.c.ke_extraction, "handle"),
        @offsetOf(abi.c.ke_extraction, "sync_component"),
        @offsetOf(abi.c.ke_extraction, "extract_copy"),
        @offsetOf(abi.c.ke_extraction, "extract_interpolate"),
        @offsetOf(abi.c.ke_extraction, "extract_custom"),
        @offsetOf(abi.c.ke_extraction, "render_entity"),
        @offsetOf(abi.c.ke_extraction, "main_entity"),
        @offsetOf(abi.c.ke_extraction, "extract"),
        @offsetOf(abi.c.ke_extraction, "run"),
        @sizeOf(abi.c.ke_extraction_handle),
        @offsetOf(abi.c.ke_extraction_handle, "ref"),
        @offsetOf(abi.c.ke_extraction_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

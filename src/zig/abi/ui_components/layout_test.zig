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
    try expectSameLayout(abi.c.ke_ui_font_handle, translated("ke_ui_font_handle"));
    try expectSameLayout(abi.c.ke_label_glyph_quad, translated("ke_label_glyph_quad"));
    try expectSameLayout(abi.c.ke_ui_quad_component, translated("ke_ui_quad_component"));
    try expectSameLayout(abi.c.ke_label_component, translated("ke_label_component"));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(std.mem.toBytes(c.KE_UI_FONT_NONE), std.mem.toBytes(abi.c.KE_UI_FONT_NONE));
    try std.testing.expectEqual(std.mem.toBytes(c.KE_UI_FONT_FAILED), std.mem.toBytes(abi.c.KE_UI_FONT_FAILED));
    try std.testing.expectEqual(@as(i128, c.KE_LABEL_MAX_TEXT), @as(i128, abi.c.KE_LABEL_MAX_TEXT));
    try std.testing.expectEqual(@as(i128, c.KE_LABEL_MAX_GLYPHS), @as(i128, abi.c.KE_LABEL_MAX_GLYPHS));
}

extern const layout_values: [33]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_ui_font_handle),
        @offsetOf(abi.c.ke_ui_font_handle, "bits"),
        @sizeOf(abi.c.ke_label_glyph_quad),
        @offsetOf(abi.c.ke_label_glyph_quad, "dst_x"),
        @offsetOf(abi.c.ke_label_glyph_quad, "dst_y"),
        @offsetOf(abi.c.ke_label_glyph_quad, "dst_w"),
        @offsetOf(abi.c.ke_label_glyph_quad, "dst_h"),
        @offsetOf(abi.c.ke_label_glyph_quad, "u0"),
        @offsetOf(abi.c.ke_label_glyph_quad, "v0"),
        @offsetOf(abi.c.ke_label_glyph_quad, "u1"),
        @offsetOf(abi.c.ke_label_glyph_quad, "v1"),
        @sizeOf(abi.c.ke_ui_quad_component),
        @offsetOf(abi.c.ke_ui_quad_component, "texture_bits"),
        @offsetOf(abi.c.ke_ui_quad_component, "dst_x"),
        @offsetOf(abi.c.ke_ui_quad_component, "dst_y"),
        @offsetOf(abi.c.ke_ui_quad_component, "dst_w"),
        @offsetOf(abi.c.ke_ui_quad_component, "dst_h"),
        @offsetOf(abi.c.ke_ui_quad_component, "u0"),
        @offsetOf(abi.c.ke_ui_quad_component, "v0"),
        @offsetOf(abi.c.ke_ui_quad_component, "u1"),
        @offsetOf(abi.c.ke_ui_quad_component, "v1"),
        @offsetOf(abi.c.ke_ui_quad_component, "color"),
        @sizeOf(abi.c.ke_label_component),
        @offsetOf(abi.c.ke_label_component, "font"),
        @offsetOf(abi.c.ke_label_component, "font_size"),
        @offsetOf(abi.c.ke_label_component, "font_handle"),
        @offsetOf(abi.c.ke_label_component, "anchor"),
        @offsetOf(abi.c.ke_label_component, "offset"),
        @offsetOf(abi.c.ke_label_component, "color"),
        @offsetOf(abi.c.ke_label_component, "text"),
        @offsetOf(abi.c.ke_label_component, "glyph_count"),
        @offsetOf(abi.c.ke_label_component, "glyphs"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

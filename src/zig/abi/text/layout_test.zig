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
    try expectSameLayout(abi.c.ke_glyph_metrics, translated("ke_glyph_metrics"));
    try expectSameLayout(abi.c.ke_font_data, translated("ke_font_data"));
    try expectSameLayout(abi.c.ke_font_loader, translated("ke_font_loader"));
    try expectSameLayout(abi.c.ke_font_loader_handle, translated("ke_font_loader_handle"));
}

extern const layout_values: [28]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_glyph_metrics),
        @offsetOf(abi.c.ke_glyph_metrics, "codepoint"),
        @offsetOf(abi.c.ke_glyph_metrics, "u0"),
        @offsetOf(abi.c.ke_glyph_metrics, "v0"),
        @offsetOf(abi.c.ke_glyph_metrics, "u1"),
        @offsetOf(abi.c.ke_glyph_metrics, "v1"),
        @offsetOf(abi.c.ke_glyph_metrics, "bearing_x"),
        @offsetOf(abi.c.ke_glyph_metrics, "bearing_y"),
        @offsetOf(abi.c.ke_glyph_metrics, "width"),
        @offsetOf(abi.c.ke_glyph_metrics, "height"),
        @offsetOf(abi.c.ke_glyph_metrics, "advance_x"),
        @sizeOf(abi.c.ke_font_data),
        @offsetOf(abi.c.ke_font_data, "atlas_rgba"),
        @offsetOf(abi.c.ke_font_data, "atlas_byte_count"),
        @offsetOf(abi.c.ke_font_data, "atlas_width"),
        @offsetOf(abi.c.ke_font_data, "atlas_height"),
        @offsetOf(abi.c.ke_font_data, "glyphs"),
        @offsetOf(abi.c.ke_font_data, "glyph_count"),
        @offsetOf(abi.c.ke_font_data, "line_height"),
        @offsetOf(abi.c.ke_font_data, "ascent"),
        @sizeOf(abi.c.ke_font_loader),
        @offsetOf(abi.c.ke_font_loader, "handle"),
        @offsetOf(abi.c.ke_font_loader, "load_font"),
        @offsetOf(abi.c.ke_font_loader, "free_font"),
        @sizeOf(abi.c.ke_font_loader_handle),
        @offsetOf(abi.c.ke_font_loader_handle, "ref"),
        @offsetOf(abi.c.ke_font_loader_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

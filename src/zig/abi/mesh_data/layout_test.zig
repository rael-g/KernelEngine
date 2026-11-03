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
    try expectSameLayout(abi.c.ke_mesh_data, translated("ke_mesh_data"));
    try expectSameLayout(abi.c.ke_material_data, translated("ke_material_data"));
    try expectSameLayout(abi.c.ke_texture_data, translated("ke_texture_data"));
    try expectSameLayout(abi.c.ke_model_data, translated("ke_model_data"));
    try expectSameLayout(abi.c.ke_mesh_shape_data, translated("ke_mesh_shape_data"));
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_MESH_PRIMITIVE_QUAD), @as(i64, abi.c.KE_MESH_PRIMITIVE_QUAD));
    try std.testing.expectEqual(@as(i64, c.KE_MESH_PRIMITIVE_PLANE), @as(i64, abi.c.KE_MESH_PRIMITIVE_PLANE));
    try std.testing.expectEqual(@as(i64, c.KE_MESH_PRIMITIVE_CUBE), @as(i64, abi.c.KE_MESH_PRIMITIVE_CUBE));
    try std.testing.expectEqual(@as(i64, c.KE_MESH_PRIMITIVE_SPHERE), @as(i64, abi.c.KE_MESH_PRIMITIVE_SPHERE));
}

extern const layout_values: [36]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_mesh_data),
        @offsetOf(abi.c.ke_mesh_data, "vertices"),
        @offsetOf(abi.c.ke_mesh_data, "vertex_count"),
        @offsetOf(abi.c.ke_mesh_data, "indices"),
        @offsetOf(abi.c.ke_mesh_data, "index_count"),
        @offsetOf(abi.c.ke_mesh_data, "material_index"),
        @offsetOf(abi.c.ke_mesh_data, "name"),
        @sizeOf(abi.c.ke_material_data),
        @offsetOf(abi.c.ke_material_data, "base_color_r"),
        @offsetOf(abi.c.ke_material_data, "base_color_g"),
        @offsetOf(abi.c.ke_material_data, "base_color_b"),
        @offsetOf(abi.c.ke_material_data, "base_color_a"),
        @offsetOf(abi.c.ke_material_data, "metallic"),
        @offsetOf(abi.c.ke_material_data, "roughness"),
        @offsetOf(abi.c.ke_material_data, "albedo_texture_index"),
        @offsetOf(abi.c.ke_material_data, "normal_map_texture_index"),
        @offsetOf(abi.c.ke_material_data, "name"),
        @sizeOf(abi.c.ke_texture_data),
        @offsetOf(abi.c.ke_texture_data, "pixels"),
        @offsetOf(abi.c.ke_texture_data, "byte_count"),
        @offsetOf(abi.c.ke_texture_data, "width"),
        @offsetOf(abi.c.ke_texture_data, "height"),
        @offsetOf(abi.c.ke_texture_data, "path"),
        @sizeOf(abi.c.ke_model_data),
        @offsetOf(abi.c.ke_model_data, "meshes"),
        @offsetOf(abi.c.ke_model_data, "mesh_count"),
        @offsetOf(abi.c.ke_model_data, "materials"),
        @offsetOf(abi.c.ke_model_data, "material_count"),
        @offsetOf(abi.c.ke_model_data, "textures"),
        @offsetOf(abi.c.ke_model_data, "texture_count"),
        @sizeOf(abi.c.ke_mesh_shape_data),
        @offsetOf(abi.c.ke_mesh_shape_data, "vertices"),
        @offsetOf(abi.c.ke_mesh_shape_data, "vertex_count"),
        @offsetOf(abi.c.ke_mesh_shape_data, "indices"),
        @offsetOf(abi.c.ke_mesh_shape_data, "index_count"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

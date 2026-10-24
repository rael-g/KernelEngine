const std = @import("std");
const abi = @import("abi");
const c = @import("c");

fn expectSameLayout(comptime A: type, comptime C: type) !void {
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
    try expectSameLayout(abi.ke_mesh_data, translated("ke_mesh_data"));
    try expectSameLayout(abi.ke_material_data, translated("ke_material_data"));
    try expectSameLayout(abi.ke_texture_data, translated("ke_texture_data"));
    try expectSameLayout(abi.ke_model_data, translated("ke_model_data"));
    try expectSameLayout(abi.ke_mesh_shape_data, translated("ke_mesh_shape_data"));
    try expectSameLayout(abi.ke_asset_loader, translated("ke_asset_loader"));
    try expectSameLayout(abi.ke_asset_loader_handle, translated("ke_asset_loader_handle"));
    try expectSameLayout(abi.ke_image_loader, translated("ke_image_loader"));
    try expectSameLayout(abi.ke_image_loader_handle, translated("ke_image_loader_handle"));
    try expectSameLayout(abi.ke_asset_resolver, translated("ke_asset_resolver"));
    try expectSameLayout(abi.ke_asset_resolver_handle, translated("ke_asset_resolver_handle"));
    try expectSameLayout(abi.ke_load_model_complete_func, c.ke_load_model_complete_func);
}

test "every enum value is the header's value" {
    try std.testing.expectEqual(@as(i64, c.KE_MESH_PRIMITIVE_QUAD), @as(i64, abi.KE_MESH_PRIMITIVE_QUAD));
    try std.testing.expectEqual(@as(i64, c.KE_MESH_PRIMITIVE_PLANE), @as(i64, abi.KE_MESH_PRIMITIVE_PLANE));
    try std.testing.expectEqual(@as(i64, c.KE_MESH_PRIMITIVE_CUBE), @as(i64, abi.KE_MESH_PRIMITIVE_CUBE));
    try std.testing.expectEqual(@as(i64, c.KE_MESH_PRIMITIVE_SPHERE), @as(i64, abi.KE_MESH_PRIMITIVE_SPHERE));
}

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
    try expectSameLayout(abi.c.ke_camera_component, translated("ke_camera_component"));
    try expectSameLayout(abi.c.ke_directional_light_component, translated("ke_directional_light_component"));
    try expectSameLayout(abi.c.ke_point_light_component, translated("ke_point_light_component"));
    try expectSameLayout(abi.c.ke_spot_light_component, translated("ke_spot_light_component"));
    try expectSameLayout(abi.c.ke_ambient_light_component, translated("ke_ambient_light_component"));
    try expectSameLayout(abi.c.ke_skybox_component, translated("ke_skybox_component"));
    try expectSameLayout(abi.c.ke_mesh_component, translated("ke_mesh_component"));
    try expectSameLayout(abi.c.ke_sprite2d_component, translated("ke_sprite2d_component"));
}

extern const layout_values: [51]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_camera_component),
        @offsetOf(abi.c.ke_camera_component, "fov"),
        @offsetOf(abi.c.ke_camera_component, "near_plane"),
        @offsetOf(abi.c.ke_camera_component, "far_plane"),
        @offsetOf(abi.c.ke_camera_component, "orthographic_size"),
        @offsetOf(abi.c.ke_camera_component, "orthographic"),
        @offsetOf(abi.c.ke_camera_component, "cull_mask"),
        @sizeOf(abi.c.ke_directional_light_component),
        @offsetOf(abi.c.ke_directional_light_component, "direction"),
        @offsetOf(abi.c.ke_directional_light_component, "color"),
        @offsetOf(abi.c.ke_directional_light_component, "intensity"),
        @offsetOf(abi.c.ke_directional_light_component, "ambient"),
        @sizeOf(abi.c.ke_point_light_component),
        @offsetOf(abi.c.ke_point_light_component, "color"),
        @offsetOf(abi.c.ke_point_light_component, "intensity"),
        @offsetOf(abi.c.ke_point_light_component, "radius"),
        @sizeOf(abi.c.ke_spot_light_component),
        @offsetOf(abi.c.ke_spot_light_component, "direction"),
        @offsetOf(abi.c.ke_spot_light_component, "color"),
        @offsetOf(abi.c.ke_spot_light_component, "intensity"),
        @offsetOf(abi.c.ke_spot_light_component, "range"),
        @offsetOf(abi.c.ke_spot_light_component, "inner_angle"),
        @offsetOf(abi.c.ke_spot_light_component, "outer_angle"),
        @sizeOf(abi.c.ke_ambient_light_component),
        @offsetOf(abi.c.ke_ambient_light_component, "color"),
        @sizeOf(abi.c.ke_skybox_component),
        @offsetOf(abi.c.ke_skybox_component, "cubemap"),
        @sizeOf(abi.c.ke_mesh_component),
        @offsetOf(abi.c.ke_mesh_component, "mesh"),
        @offsetOf(abi.c.ke_mesh_component, "material"),
        @offsetOf(abi.c.ke_mesh_component, "primitive"),
        @offsetOf(abi.c.ke_mesh_component, "base_color"),
        @offsetOf(abi.c.ke_mesh_component, "roughness"),
        @offsetOf(abi.c.ke_mesh_component, "alpha_mode"),
        @offsetOf(abi.c.ke_mesh_component, "alpha_cutoff"),
        @offsetOf(abi.c.ke_mesh_component, "ior"),
        @offsetOf(abi.c.ke_mesh_component, "distortion_strength"),
        @offsetOf(abi.c.ke_mesh_component, "layers"),
        @sizeOf(abi.c.ke_sprite2d_component),
        @offsetOf(abi.c.ke_sprite2d_component, "texture"),
        @offsetOf(abi.c.ke_sprite2d_component, "region"),
        @offsetOf(abi.c.ke_sprite2d_component, "size"),
        @offsetOf(abi.c.ke_sprite2d_component, "pivot"),
        @offsetOf(abi.c.ke_sprite2d_component, "flip_h"),
        @offsetOf(abi.c.ke_sprite2d_component, "flip_v"),
        @offsetOf(abi.c.ke_sprite2d_component, "color"),
        @offsetOf(abi.c.ke_sprite2d_component, "alpha_mode"),
        @offsetOf(abi.c.ke_sprite2d_component, "alpha_cutoff"),
        @offsetOf(abi.c.ke_sprite2d_component, "texture_handle"),
        @offsetOf(abi.c.ke_sprite2d_component, "attached"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

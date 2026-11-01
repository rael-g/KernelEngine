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
    try expectSameLayout(abi.c.ke_render_scene_component_ids, translated("ke_render_scene_component_ids"));
    try expectSameLayout(abi.c.ke_camera_frustum, translated("ke_camera_frustum"));
    try expectSameLayout(abi.c.ke_render_frame, translated("ke_render_frame"));
    try expectSameLayout(abi.c.ke_render_frame_handle, translated("ke_render_frame_handle"));
    try expectSameLayout(abi.c.ke_render_scene_resolve, translated("ke_render_scene_resolve"));
    try expectSameLayout(abi.c.ke_render_scene_resolve_handle, translated("ke_render_scene_resolve_handle"));
    try expectSameLayout(abi.c.ke_render_camera, translated("ke_render_camera"));
    try expectSameLayout(abi.c.ke_render_camera_handle, translated("ke_render_camera_handle"));
    try expectSameLayout(abi.c.ke_render_pass_ctx, translated("ke_render_pass_ctx"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_gpu_bind_group")) try expectSameLayout(abi.c.ke_gpu_bind_group, c.ke_gpu_bind_group);
    if (@hasDecl(c, "ke_gpu_bind_group_layout")) try expectSameLayout(abi.c.ke_gpu_bind_group_layout, c.ke_gpu_bind_group_layout);
    if (@hasDecl(c, "ke_gpu_buffer")) try expectSameLayout(abi.c.ke_gpu_buffer, c.ke_gpu_buffer);
    if (@hasDecl(c, "ke_gpu_buffer_usage")) try expectSameLayout(abi.c.ke_gpu_buffer_usage, c.ke_gpu_buffer_usage);
    if (@hasDecl(c, "ke_gpu_pipeline")) try expectSameLayout(abi.c.ke_gpu_pipeline, c.ke_gpu_pipeline);
    if (@hasDecl(c, "ke_gpu_queue")) try expectSameLayout(abi.c.ke_gpu_queue, c.ke_gpu_queue);
    if (@hasDecl(c, "ke_gpu_sampler")) try expectSameLayout(abi.c.ke_gpu_sampler, c.ke_gpu_sampler);
    if (@hasDecl(c, "ke_gpu_shader_module")) try expectSameLayout(abi.c.ke_gpu_shader_module, c.ke_gpu_shader_module);
    if (@hasDecl(c, "ke_gpu_shader_stage")) try expectSameLayout(abi.c.ke_gpu_shader_stage, c.ke_gpu_shader_stage);
    if (@hasDecl(c, "ke_gpu_texture")) try expectSameLayout(abi.c.ke_gpu_texture, c.ke_gpu_texture);
    if (@hasDecl(c, "ke_gpu_texture_aspect")) try expectSameLayout(abi.c.ke_gpu_texture_aspect, c.ke_gpu_texture_aspect);
    if (@hasDecl(c, "ke_gpu_texture_usage")) try expectSameLayout(abi.c.ke_gpu_texture_usage, c.ke_gpu_texture_usage);
    if (@hasDecl(c, "ke_gpu_texture_view")) try expectSameLayout(abi.c.ke_gpu_texture_view, c.ke_gpu_texture_view);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_CAMERA, abi.c.KE_COMPONENT_NAME_CAMERA);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, abi.c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_POINT_LIGHT, abi.c.KE_COMPONENT_NAME_POINT_LIGHT);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_SPOT_LIGHT, abi.c.KE_COMPONENT_NAME_SPOT_LIGHT);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_AMBIENT_LIGHT, abi.c.KE_COMPONENT_NAME_AMBIENT_LIGHT);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_SKYBOX, abi.c.KE_COMPONENT_NAME_SKYBOX);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_MESH, abi.c.KE_COMPONENT_NAME_MESH);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_SPRITE2D, abi.c.KE_COMPONENT_NAME_SPRITE2D);
    try std.testing.expectEqualStrings(c.KE_RENDER_GBUFFER_ALBEDO, abi.c.KE_RENDER_GBUFFER_ALBEDO);
    try std.testing.expectEqualStrings(c.KE_RENDER_GBUFFER_NORMAL, abi.c.KE_RENDER_GBUFFER_NORMAL);
    try std.testing.expectEqualStrings(c.KE_RENDER_GBUFFER_EMISSIVE, abi.c.KE_RENDER_GBUFFER_EMISSIVE);
    try std.testing.expectEqualStrings(c.KE_RENDER_SHADOW_LIGHT, abi.c.KE_RENDER_SHADOW_LIGHT);
    try std.testing.expectEqualStrings(c.KE_RENDER_SHADOW_DEPTH, abi.c.KE_RENDER_SHADOW_DEPTH);
    try std.testing.expectEqualStrings(c.KE_RENDER_CLUSTER_POINT_LIGHTS, abi.c.KE_RENDER_CLUSTER_POINT_LIGHTS);
    try std.testing.expectEqualStrings(c.KE_RENDER_CLUSTER_SPOT_LIGHTS, abi.c.KE_RENDER_CLUSTER_SPOT_LIGHTS);
    try std.testing.expectEqualStrings(c.KE_RENDER_CLUSTER_POINT_INDICES, abi.c.KE_RENDER_CLUSTER_POINT_INDICES);
    try std.testing.expectEqualStrings(c.KE_RENDER_CLUSTER_POINT_COUNTS, abi.c.KE_RENDER_CLUSTER_POINT_COUNTS);
    try std.testing.expectEqualStrings(c.KE_RENDER_CLUSTER_SPOT_INDICES, abi.c.KE_RENDER_CLUSTER_SPOT_INDICES);
    try std.testing.expectEqualStrings(c.KE_RENDER_CLUSTER_SPOT_COUNTS, abi.c.KE_RENDER_CLUSTER_SPOT_COUNTS);
    try std.testing.expectEqualStrings(c.KE_RENDER_CLUSTER_GRID, abi.c.KE_RENDER_CLUSTER_GRID);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_UI_QUAD, abi.c.KE_COMPONENT_NAME_UI_QUAD);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_LABEL, abi.c.KE_COMPONENT_NAME_LABEL);
}

extern const layout_values: [49]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_render_scene_component_ids),
        @offsetOf(abi.c.ke_render_scene_component_ids, "mesh"),
        @offsetOf(abi.c.ke_render_scene_component_ids, "camera"),
        @offsetOf(abi.c.ke_render_scene_component_ids, "directional_light"),
        @offsetOf(abi.c.ke_render_scene_component_ids, "point_light"),
        @offsetOf(abi.c.ke_render_scene_component_ids, "spot_light"),
        @offsetOf(abi.c.ke_render_scene_component_ids, "ambient_light"),
        @offsetOf(abi.c.ke_render_scene_component_ids, "skybox"),
        @offsetOf(abi.c.ke_render_scene_component_ids, "sprite2d"),
        @offsetOf(abi.c.ke_render_scene_component_ids, "label"),
        @offsetOf(abi.c.ke_render_scene_component_ids, "world_transform"),
        @sizeOf(abi.c.ke_camera_frustum),
        @offsetOf(abi.c.ke_camera_frustum, "tan_half_fov_y"),
        @offsetOf(abi.c.ke_camera_frustum, "aspect"),
        @offsetOf(abi.c.ke_camera_frustum, "near_plane"),
        @offsetOf(abi.c.ke_camera_frustum, "far_plane"),
        @sizeOf(abi.c.ke_render_frame),
        @offsetOf(abi.c.ke_render_frame, "handle"),
        @offsetOf(abi.c.ke_render_frame, "frame_cid"),
        @sizeOf(abi.c.ke_render_frame_handle),
        @offsetOf(abi.c.ke_render_frame_handle, "ref"),
        @offsetOf(abi.c.ke_render_frame_handle, "destroy"),
        @sizeOf(abi.c.ke_render_scene_resolve),
        @offsetOf(abi.c.ke_render_scene_resolve, "handle"),
        @offsetOf(abi.c.ke_render_scene_resolve, "component_ids"),
        @sizeOf(abi.c.ke_render_scene_resolve_handle),
        @offsetOf(abi.c.ke_render_scene_resolve_handle, "ref"),
        @offsetOf(abi.c.ke_render_scene_resolve_handle, "destroy"),
        @sizeOf(abi.c.ke_render_camera),
        @offsetOf(abi.c.ke_render_camera, "handle"),
        @offsetOf(abi.c.ke_render_camera, "view"),
        @offsetOf(abi.c.ke_render_camera, "view_rotation"),
        @offsetOf(abi.c.ke_render_camera, "projection"),
        @offsetOf(abi.c.ke_render_camera, "perspective_projection"),
        @offsetOf(abi.c.ke_render_camera, "perspective_frustum"),
        @sizeOf(abi.c.ke_render_camera_handle),
        @offsetOf(abi.c.ke_render_camera_handle, "ref"),
        @offsetOf(abi.c.ke_render_camera_handle, "destroy"),
        @sizeOf(abi.c.ke_render_pass_ctx),
        @offsetOf(abi.c.ke_render_pass_ctx, "handle"),
        @offsetOf(abi.c.ke_render_pass_ctx, "read"),
        @offsetOf(abi.c.ke_render_pass_ctx, "write"),
        @offsetOf(abi.c.ke_render_pass_ctx, "begin_render"),
        @offsetOf(abi.c.ke_render_pass_ctx, "begin_compute"),
        @offsetOf(abi.c.ke_render_pass_ctx, "encoder"),
        @offsetOf(abi.c.ke_render_pass_ctx, "query_ext"),
        @offsetOf(abi.c.ke_render_pass_ctx, "backbuffer_size"),
        @offsetOf(abi.c.ke_render_pass_ctx, "color_source"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

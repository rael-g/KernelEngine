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
    try expectSameLayout(abi.c.ke_render_resource_params, translated("ke_render_resource_params"));
    try expectSameLayout(abi.c.ke_render_frame_globals, translated("ke_render_frame_globals"));
    try expectSameLayout(abi.c.ke_render_lighting, translated("ke_render_lighting"));
    try expectSameLayout(abi.c.ke_render_pass_io, translated("ke_render_pass_io"));
    try expectSameLayout(abi.c.ke_render_scene_component_ids, translated("ke_render_scene_component_ids"));
    try expectSameLayout(abi.c.ke_render_service, translated("ke_render_service"));
    try expectSameLayout(abi.c.ke_render_service_handle, translated("ke_render_service_handle"));
    try expectSameLayout(abi.c.ke_render_frame, translated("ke_render_frame"));
    try expectSameLayout(abi.c.ke_render_frame_handle, translated("ke_render_frame_handle"));
    try expectSameLayout(abi.c.ke_render_scene_resolve, translated("ke_render_scene_resolve"));
    try expectSameLayout(abi.c.ke_render_scene_resolve_handle, translated("ke_render_scene_resolve_handle"));
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
    if (@hasDecl(c, "ke_render_chain_link")) try expectSameLayout(abi.c.ke_render_chain_link, c.ke_render_chain_link);
    if (@hasDecl(c, "ke_render_material_binding")) try expectSameLayout(abi.c.ke_render_material_binding, c.ke_render_material_binding);
    if (@hasDecl(c, "ke_render_resource_set")) try expectSameLayout(abi.c.ke_render_resource_set, c.ke_render_resource_set);
    if (@hasDecl(c, "ke_render_shader_layout")) try expectSameLayout(abi.c.ke_render_shader_layout, c.ke_render_shader_layout);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_RESOURCE_TEXTURE), @as(i64, abi.c.KE_RENDER_RESOURCE_TEXTURE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_RESOURCE_BUFFER), @as(i64, abi.c.KE_RENDER_RESOURCE_BUFFER));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_SIZE_ABSOLUTE), @as(i64, abi.c.KE_RENDER_SIZE_ABSOLUTE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER), @as(i64, abi.c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_STAGE_OPAQUE), @as(i64, abi.c.KE_RENDER_STAGE_OPAQUE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_STAGE_SKY), @as(i64, abi.c.KE_RENDER_STAGE_SKY));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_STAGE_TRANSPARENT), @as(i64, abi.c.KE_RENDER_STAGE_TRANSPARENT));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_STAGE_HDR_POST), @as(i64, abi.c.KE_RENDER_STAGE_HDR_POST));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_STAGE_TONEMAP), @as(i64, abi.c.KE_RENDER_STAGE_TONEMAP));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_STAGE_LDR_POST), @as(i64, abi.c.KE_RENDER_STAGE_LDR_POST));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_STAGE_OVERLAY), @as(i64, abi.c.KE_RENDER_STAGE_OVERLAY));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_STAGE_COUNT), @as(i64, abi.c.KE_RENDER_STAGE_COUNT));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_CHAIN_DRAW_OVER), @as(i64, abi.c.KE_RENDER_CHAIN_DRAW_OVER));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_CHAIN_SAMPLE_OVER), @as(i64, abi.c.KE_RENDER_CHAIN_SAMPLE_OVER));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_CHAIN_REPLACE), @as(i64, abi.c.KE_RENDER_CHAIN_REPLACE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_DEPTH_NONE), @as(i64, abi.c.KE_RENDER_DEPTH_NONE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_DEPTH_TEST), @as(i64, abi.c.KE_RENDER_DEPTH_TEST));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_DEPTH_WRITE), @as(i64, abi.c.KE_RENDER_DEPTH_WRITE));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqualStrings(c.KE_RENDER_FRAME_COLOR, abi.c.KE_RENDER_FRAME_COLOR);
    try std.testing.expectEqualStrings(c.KE_RENDER_FRAME_DEPTH, abi.c.KE_RENDER_FRAME_DEPTH);
    try std.testing.expectEqual(@as(i128, c.KE_RENDER_CHAIN_NONE), @as(i128, abi.c.KE_RENDER_CHAIN_NONE));
}

extern const layout_values: [112]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_render_resource_params),
        @offsetOf(abi.c.ke_render_resource_params, "name"),
        @offsetOf(abi.c.ke_render_resource_params, "type"),
        @offsetOf(abi.c.ke_render_resource_params, "format"),
        @offsetOf(abi.c.ke_render_resource_params, "size_mode"),
        @offsetOf(abi.c.ke_render_resource_params, "width"),
        @offsetOf(abi.c.ke_render_resource_params, "height"),
        @offsetOf(abi.c.ke_render_resource_params, "scale_x"),
        @offsetOf(abi.c.ke_render_resource_params, "scale_y"),
        @offsetOf(abi.c.ke_render_resource_params, "clear_value"),
        @sizeOf(abi.c.ke_render_frame_globals),
        @offsetOf(abi.c.ke_render_frame_globals, "view"),
        @offsetOf(abi.c.ke_render_frame_globals, "proj"),
        @offsetOf(abi.c.ke_render_frame_globals, "view_proj"),
        @offsetOf(abi.c.ke_render_frame_globals, "inv_view_proj"),
        @offsetOf(abi.c.ke_render_frame_globals, "inv_proj"),
        @offsetOf(abi.c.ke_render_frame_globals, "camera_pos"),
        @offsetOf(abi.c.ke_render_frame_globals, "viewport"),
        @offsetOf(abi.c.ke_render_frame_globals, "time"),
        @offsetOf(abi.c.ke_render_frame_globals, "dt"),
        @offsetOf(abi.c.ke_render_frame_globals, "near_plane"),
        @offsetOf(abi.c.ke_render_frame_globals, "far_plane"),
        @sizeOf(abi.c.ke_render_lighting),
        @offsetOf(abi.c.ke_render_lighting, "direction"),
        @offsetOf(abi.c.ke_render_lighting, "color"),
        @offsetOf(abi.c.ke_render_lighting, "ambient"),
        @sizeOf(abi.c.ke_render_pass_io),
        @offsetOf(abi.c.ke_render_pass_io, "name"),
        @offsetOf(abi.c.ke_render_pass_io, "reads"),
        @offsetOf(abi.c.ke_render_pass_io, "reads_count"),
        @offsetOf(abi.c.ke_render_pass_io, "writes"),
        @offsetOf(abi.c.ke_render_pass_io, "writes_count"),
        @offsetOf(abi.c.ke_render_pass_io, "chain"),
        @offsetOf(abi.c.ke_render_pass_io, "depth"),
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
        @sizeOf(abi.c.ke_render_service),
        @offsetOf(abi.c.ke_render_service, "handle"),
        @offsetOf(abi.c.ke_render_service, "declare"),
        @offsetOf(abi.c.ke_render_service, "import_texture"),
        @offsetOf(abi.c.ke_render_service, "import_tag"),
        @offsetOf(abi.c.ke_render_service, "import_buffer"),
        @offsetOf(abi.c.ke_render_service, "cid"),
        @offsetOf(abi.c.ke_render_service, "begin_pass"),
        @offsetOf(abi.c.ke_render_service, "end_pass"),
        @offsetOf(abi.c.ke_render_service, "begin_frame"),
        @offsetOf(abi.c.ke_render_service, "end_frame"),
        @offsetOf(abi.c.ke_render_service, "upload_mesh"),
        @offsetOf(abi.c.ke_render_service, "mesh_buffers"),
        @offsetOf(abi.c.ke_render_service, "set_clear_color"),
        @offsetOf(abi.c.ke_render_service, "upload_texture"),
        @offsetOf(abi.c.ke_render_service, "create_material"),
        @offsetOf(abi.c.ke_render_service, "material_binding"),
        @offsetOf(abi.c.ke_render_service, "material_alpha_mode"),
        @offsetOf(abi.c.ke_render_service, "material_alpha_cutoff"),
        @offsetOf(abi.c.ke_render_service, "upload_cubemap"),
        @offsetOf(abi.c.ke_render_service, "texture_view"),
        @offsetOf(abi.c.ke_render_service, "resource_view"),
        @offsetOf(abi.c.ke_render_service, "resource_texture"),
        @offsetOf(abi.c.ke_render_service, "resource_buffer"),
        @offsetOf(abi.c.ke_render_service, "resource_buffer_size"),
        @offsetOf(abi.c.ke_render_service, "backbuffer_size"),
        @offsetOf(abi.c.ke_render_service, "upload"),
        @offsetOf(abi.c.ke_render_service, "get_or_create_pipeline"),
        @offsetOf(abi.c.ke_render_service, "material_shader"),
        @offsetOf(abi.c.ke_render_service, "retain_mesh"),
        @offsetOf(abi.c.ke_render_service, "release_mesh"),
        @offsetOf(abi.c.ke_render_service, "retain_texture"),
        @offsetOf(abi.c.ke_render_service, "release_texture"),
        @offsetOf(abi.c.ke_render_service, "retain_material"),
        @offsetOf(abi.c.ke_render_service, "release_material"),
        @offsetOf(abi.c.ke_render_service, "try_get_mesh"),
        @offsetOf(abi.c.ke_render_service, "try_get_texture"),
        @offsetOf(abi.c.ke_render_service, "try_get_material"),
        @offsetOf(abi.c.ke_render_service, "white_texture"),
        @offsetOf(abi.c.ke_render_service, "load_shader"),
        @offsetOf(abi.c.ke_render_service, "set_frame_globals"),
        @offsetOf(abi.c.ke_render_service, "frame_globals"),
        @offsetOf(abi.c.ke_render_service, "set_lighting"),
        @offsetOf(abi.c.ke_render_service, "lighting"),
        @offsetOf(abi.c.ke_render_service, "resource_binder"),
        @offsetOf(abi.c.ke_render_service, "backbuffer_format"),
        @offsetOf(abi.c.ke_render_service, "resource_format"),
        @offsetOf(abi.c.ke_render_service, "resource_generation"),
        @offsetOf(abi.c.ke_render_service, "join_chain"),
        @offsetOf(abi.c.ke_render_service, "leave_chain"),
        @offsetOf(abi.c.ke_render_service, "chain_format"),
        @sizeOf(abi.c.ke_render_service_handle),
        @offsetOf(abi.c.ke_render_service_handle, "ref"),
        @offsetOf(abi.c.ke_render_service_handle, "destroy"),
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
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

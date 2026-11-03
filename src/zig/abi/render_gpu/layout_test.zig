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
    try expectSameLayout(abi.c.ke_ndc_convention, translated("ke_ndc_convention"));
    try expectSameLayout(abi.c.ke_gpu_clear_value, translated("ke_gpu_clear_value"));
    try expectSameLayout(abi.c.ke_gpu_capabilities, translated("ke_gpu_capabilities"));
    try expectSameLayout(abi.c.ke_gpu_buffer_params, translated("ke_gpu_buffer_params"));
    try expectSameLayout(abi.c.ke_gpu_texture_params, translated("ke_gpu_texture_params"));
    try expectSameLayout(abi.c.ke_gpu_texture_view_params, translated("ke_gpu_texture_view_params"));
    try expectSameLayout(abi.c.ke_gpu_sampler_params, translated("ke_gpu_sampler_params"));
    try expectSameLayout(abi.c.ke_gpu_shader_module_params, translated("ke_gpu_shader_module_params"));
    try expectSameLayout(abi.c.ke_gpu_vertex_attribute, translated("ke_gpu_vertex_attribute"));
    try expectSameLayout(abi.c.ke_gpu_vertex_buffer_layout, translated("ke_gpu_vertex_buffer_layout"));
    try expectSameLayout(abi.c.ke_gpu_blend_state, translated("ke_gpu_blend_state"));
    try expectSameLayout(abi.c.ke_gpu_depth_stencil_state, translated("ke_gpu_depth_stencil_state"));
    try expectSameLayout(abi.c.ke_gpu_bind_group_layout_entry, translated("ke_gpu_bind_group_layout_entry"));
    try expectSameLayout(abi.c.ke_gpu_bind_group_layout_params, translated("ke_gpu_bind_group_layout_params"));
    try expectSameLayout(abi.c.ke_gpu_bind_group_entry, translated("ke_gpu_bind_group_entry"));
    try expectSameLayout(abi.c.ke_gpu_bind_group_params, translated("ke_gpu_bind_group_params"));
    try expectSameLayout(abi.c.ke_gpu_render_pipeline_params, translated("ke_gpu_render_pipeline_params"));
    try expectSameLayout(abi.c.ke_gpu_compute_pipeline_params, translated("ke_gpu_compute_pipeline_params"));
    try expectSameLayout(abi.c.ke_gpu_color_attachment, translated("ke_gpu_color_attachment"));
    try expectSameLayout(abi.c.ke_gpu_depth_stencil_attachment, translated("ke_gpu_depth_stencil_attachment"));
    try expectSameLayout(abi.c.ke_gpu_render_pass_params, translated("ke_gpu_render_pass_params"));
    try expectSameLayout(abi.c.ke_gpu_command_encoder_params, translated("ke_gpu_command_encoder_params"));
    try expectSameLayout(abi.c.ke_gpu_compute_pass_params, translated("ke_gpu_compute_pass_params"));
    try expectSameLayout(abi.c.ke_gpu_command_buffer, translated("ke_gpu_command_buffer"));
    try expectSameLayout(abi.c.ke_render_binding_hint, translated("ke_render_binding_hint"));
    try expectSameLayout(abi.c.ke_render_shader_binding, translated("ke_render_shader_binding"));
    try expectSameLayout(abi.c.ke_render_shader_layout_params, translated("ke_render_shader_layout_params"));
    try expectSameLayout(abi.c.ke_render_material_data, translated("ke_render_material_data"));
    try expectSameLayout(abi.c.ke_gpu_command_encoder_handle, translated("ke_gpu_command_encoder_handle"));
    try expectSameLayout(abi.c.ke_gpu_command_buffer_handle, translated("ke_gpu_command_buffer_handle"));
    try expectSameLayout(abi.c.ke_gpu_device, translated("ke_gpu_device"));
    try expectSameLayout(abi.c.ke_gpu_device_handle, translated("ke_gpu_device_handle"));
    try expectSameLayout(abi.c.ke_gpu_render_pass, translated("ke_gpu_render_pass"));
    try expectSameLayout(abi.c.ke_gpu_compute_pass, translated("ke_gpu_compute_pass"));
    try expectSameLayout(abi.c.ke_gpu_command_encoder, translated("ke_gpu_command_encoder"));
    try expectSameLayout(abi.c.ke_gpu_render_target, translated("ke_gpu_render_target"));
    try expectSameLayout(abi.c.ke_gpu_render_target_handle, translated("ke_gpu_render_target_handle"));
    try expectSameLayout(abi.c.ke_render_resource_binder, translated("ke_render_resource_binder"));
    try expectSameLayout(abi.c.ke_render_resource_binder_handle, translated("ke_render_resource_binder_handle"));
    if (@hasDecl(c, "ke_gpu_bind_group")) try expectSameLayout(abi.c.ke_gpu_bind_group, c.ke_gpu_bind_group);
    if (@hasDecl(c, "ke_gpu_bind_group_layout")) try expectSameLayout(abi.c.ke_gpu_bind_group_layout, c.ke_gpu_bind_group_layout);
    if (@hasDecl(c, "ke_gpu_buffer")) try expectSameLayout(abi.c.ke_gpu_buffer, c.ke_gpu_buffer);
    if (@hasDecl(c, "ke_gpu_buffer_mapped_func")) try expectSameLayout(abi.c.ke_gpu_buffer_mapped_func, c.ke_gpu_buffer_mapped_func);
    if (@hasDecl(c, "ke_gpu_buffer_usage")) try expectSameLayout(abi.c.ke_gpu_buffer_usage, c.ke_gpu_buffer_usage);
    if (@hasDecl(c, "ke_gpu_pipeline")) try expectSameLayout(abi.c.ke_gpu_pipeline, c.ke_gpu_pipeline);
    if (@hasDecl(c, "ke_gpu_pipeline_ready_func")) try expectSameLayout(abi.c.ke_gpu_pipeline_ready_func, c.ke_gpu_pipeline_ready_func);
    if (@hasDecl(c, "ke_gpu_queue")) try expectSameLayout(abi.c.ke_gpu_queue, c.ke_gpu_queue);
    if (@hasDecl(c, "ke_gpu_sampler")) try expectSameLayout(abi.c.ke_gpu_sampler, c.ke_gpu_sampler);
    if (@hasDecl(c, "ke_gpu_shader_module")) try expectSameLayout(abi.c.ke_gpu_shader_module, c.ke_gpu_shader_module);
    if (@hasDecl(c, "ke_gpu_shader_stage")) try expectSameLayout(abi.c.ke_gpu_shader_stage, c.ke_gpu_shader_stage);
    if (@hasDecl(c, "ke_gpu_texture")) try expectSameLayout(abi.c.ke_gpu_texture, c.ke_gpu_texture);
    if (@hasDecl(c, "ke_gpu_texture_aspect")) try expectSameLayout(abi.c.ke_gpu_texture_aspect, c.ke_gpu_texture_aspect);
    if (@hasDecl(c, "ke_gpu_texture_usage")) try expectSameLayout(abi.c.ke_gpu_texture_usage, c.ke_gpu_texture_usage);
    if (@hasDecl(c, "ke_gpu_texture_view")) try expectSameLayout(abi.c.ke_gpu_texture_view, c.ke_gpu_texture_view);
    if (@hasDecl(c, "ke_render_material_binding")) try expectSameLayout(abi.c.ke_render_material_binding, c.ke_render_material_binding);
    if (@hasDecl(c, "ke_render_resource_set")) try expectSameLayout(abi.c.ke_render_resource_set, c.ke_render_resource_set);
    if (@hasDecl(c, "ke_render_shader_layout")) try expectSameLayout(abi.c.ke_render_shader_layout, c.ke_render_shader_layout);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_GPU_INDEX_FORMAT_UINT16), @as(i64, abi.c.KE_GPU_INDEX_FORMAT_UINT16));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_INDEX_FORMAT_UINT32), @as(i64, abi.c.KE_GPU_INDEX_FORMAT_UINT32));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_INVALID), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_INVALID));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_RGBA8_SRGB), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_RGBA8_SRGB));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_R32_FLOAT), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_R32_FLOAT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_R16_FLOAT), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_R16_FLOAT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_D16_UNORM), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_D16_UNORM));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_D24_UNORM_S8_UINT), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_D24_UNORM_S8_UINT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_RGBA32_FLOAT), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_RGBA32_FLOAT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_RG32_FLOAT), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_RG32_FLOAT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_R8_UNORM), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_R8_UNORM));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_BC1_RGBA_UNORM), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_BC1_RGBA_UNORM));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_BC3_RGBA_UNORM), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_BC3_RGBA_UNORM));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_BC5_RG_UNORM), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_BC5_RG_UNORM));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_FORMAT_BC7_RGBA_UNORM), @as(i64, abi.c.KE_GPU_TEXTURE_FORMAT_BC7_RGBA_UNORM));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_DIM_1D), @as(i64, abi.c.KE_GPU_TEXTURE_DIM_1D));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_DIM_2D), @as(i64, abi.c.KE_GPU_TEXTURE_DIM_2D));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_DIM_3D), @as(i64, abi.c.KE_GPU_TEXTURE_DIM_3D));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_TEXTURE_DIM_CUBE), @as(i64, abi.c.KE_GPU_TEXTURE_DIM_CUBE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_LOAD_OP_LOAD), @as(i64, abi.c.KE_GPU_LOAD_OP_LOAD));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_LOAD_OP_CLEAR), @as(i64, abi.c.KE_GPU_LOAD_OP_CLEAR));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_LOAD_OP_DONT_CARE), @as(i64, abi.c.KE_GPU_LOAD_OP_DONT_CARE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_STORE_OP_STORE), @as(i64, abi.c.KE_GPU_STORE_OP_STORE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_STORE_OP_DONT_CARE), @as(i64, abi.c.KE_GPU_STORE_OP_DONT_CARE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_FILTER_NEAREST), @as(i64, abi.c.KE_GPU_FILTER_NEAREST));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_FILTER_LINEAR), @as(i64, abi.c.KE_GPU_FILTER_LINEAR));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_SAMPLER_MIPMAP_NEAREST), @as(i64, abi.c.KE_GPU_SAMPLER_MIPMAP_NEAREST));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_SAMPLER_MIPMAP_LINEAR), @as(i64, abi.c.KE_GPU_SAMPLER_MIPMAP_LINEAR));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_ADDRESS_MODE_REPEAT), @as(i64, abi.c.KE_GPU_ADDRESS_MODE_REPEAT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_ADDRESS_MODE_MIRRORED_REPEAT), @as(i64, abi.c.KE_GPU_ADDRESS_MODE_MIRRORED_REPEAT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_ADDRESS_MODE_CLAMP_TO_EDGE), @as(i64, abi.c.KE_GPU_ADDRESS_MODE_CLAMP_TO_EDGE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_ADDRESS_MODE_CLAMP_TO_BORDER), @as(i64, abi.c.KE_GPU_ADDRESS_MODE_CLAMP_TO_BORDER));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_COMPARE_UNDEFINED), @as(i64, abi.c.KE_GPU_COMPARE_UNDEFINED));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_COMPARE_NEVER), @as(i64, abi.c.KE_GPU_COMPARE_NEVER));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_COMPARE_LESS), @as(i64, abi.c.KE_GPU_COMPARE_LESS));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_COMPARE_EQUAL), @as(i64, abi.c.KE_GPU_COMPARE_EQUAL));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_COMPARE_LESS_EQUAL), @as(i64, abi.c.KE_GPU_COMPARE_LESS_EQUAL));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_COMPARE_GREATER), @as(i64, abi.c.KE_GPU_COMPARE_GREATER));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_COMPARE_NOT_EQUAL), @as(i64, abi.c.KE_GPU_COMPARE_NOT_EQUAL));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_COMPARE_GREATER_EQUAL), @as(i64, abi.c.KE_GPU_COMPARE_GREATER_EQUAL));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_COMPARE_ALWAYS), @as(i64, abi.c.KE_GPU_COMPARE_ALWAYS));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST), @as(i64, abi.c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP), @as(i64, abi.c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_PRIMITIVE_TOPOLOGY_LINE_LIST), @as(i64, abi.c.KE_GPU_PRIMITIVE_TOPOLOGY_LINE_LIST));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_PRIMITIVE_TOPOLOGY_LINE_STRIP), @as(i64, abi.c.KE_GPU_PRIMITIVE_TOPOLOGY_LINE_STRIP));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_PRIMITIVE_TOPOLOGY_POINT_LIST), @as(i64, abi.c.KE_GPU_PRIMITIVE_TOPOLOGY_POINT_LIST));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_CULL_MODE_NONE), @as(i64, abi.c.KE_GPU_CULL_MODE_NONE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_CULL_MODE_FRONT), @as(i64, abi.c.KE_GPU_CULL_MODE_FRONT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_CULL_MODE_BACK), @as(i64, abi.c.KE_GPU_CULL_MODE_BACK));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_FRONT_FACE_CCW), @as(i64, abi.c.KE_GPU_FRONT_FACE_CCW));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_FRONT_FACE_CW), @as(i64, abi.c.KE_GPU_FRONT_FACE_CW));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_ZERO), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_ZERO));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_ONE), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_ONE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_SRC_ALPHA), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_SRC_ALPHA));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_DST_ALPHA), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_DST_ALPHA));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_ONE_MINUS_DST_ALPHA), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_ONE_MINUS_DST_ALPHA));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_SRC_COLOR), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_SRC_COLOR));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_COLOR), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_COLOR));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_DST_COLOR), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_DST_COLOR));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_FACTOR_ONE_MINUS_DST_COLOR), @as(i64, abi.c.KE_GPU_BLEND_FACTOR_ONE_MINUS_DST_COLOR));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_OP_ADD), @as(i64, abi.c.KE_GPU_BLEND_OP_ADD));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_OP_SUBTRACT), @as(i64, abi.c.KE_GPU_BLEND_OP_SUBTRACT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_OP_REVERSE_SUBTRACT), @as(i64, abi.c.KE_GPU_BLEND_OP_REVERSE_SUBTRACT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_OP_MIN), @as(i64, abi.c.KE_GPU_BLEND_OP_MIN));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BLEND_OP_MAX), @as(i64, abi.c.KE_GPU_BLEND_OP_MAX));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_STENCIL_OP_KEEP), @as(i64, abi.c.KE_GPU_STENCIL_OP_KEEP));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_STENCIL_OP_ZERO), @as(i64, abi.c.KE_GPU_STENCIL_OP_ZERO));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_STENCIL_OP_REPLACE), @as(i64, abi.c.KE_GPU_STENCIL_OP_REPLACE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_STENCIL_OP_INVERT), @as(i64, abi.c.KE_GPU_STENCIL_OP_INVERT));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_STENCIL_OP_INCREMENT_CLAMP), @as(i64, abi.c.KE_GPU_STENCIL_OP_INCREMENT_CLAMP));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_STENCIL_OP_DECREMENT_CLAMP), @as(i64, abi.c.KE_GPU_STENCIL_OP_DECREMENT_CLAMP));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_VERTEX_STEP_MODE_VERTEX), @as(i64, abi.c.KE_GPU_VERTEX_STEP_MODE_VERTEX));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_VERTEX_STEP_MODE_INSTANCE), @as(i64, abi.c.KE_GPU_VERTEX_STEP_MODE_INSTANCE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_VERTEX_FORMAT_FLOAT32X2), @as(i64, abi.c.KE_GPU_VERTEX_FORMAT_FLOAT32X2));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_VERTEX_FORMAT_FLOAT32X3), @as(i64, abi.c.KE_GPU_VERTEX_FORMAT_FLOAT32X3));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_VERTEX_FORMAT_FLOAT32X4), @as(i64, abi.c.KE_GPU_VERTEX_FORMAT_FLOAT32X4));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_VERTEX_FORMAT_SINT16X2), @as(i64, abi.c.KE_GPU_VERTEX_FORMAT_SINT16X2));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_VERTEX_FORMAT_SINT16X4), @as(i64, abi.c.KE_GPU_VERTEX_FORMAT_SINT16X4));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_VERTEX_FORMAT_UINT8X4_UNORM), @as(i64, abi.c.KE_GPU_VERTEX_FORMAT_UINT8X4_UNORM));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_VERTEX_FORMAT_UINT8X4), @as(i64, abi.c.KE_GPU_VERTEX_FORMAT_UINT8X4));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BINDING_TYPE_BUFFER), @as(i64, abi.c.KE_GPU_BINDING_TYPE_BUFFER));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BINDING_TYPE_SAMPLER), @as(i64, abi.c.KE_GPU_BINDING_TYPE_SAMPLER));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BINDING_TYPE_TEXTURE), @as(i64, abi.c.KE_GPU_BINDING_TYPE_TEXTURE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BINDING_TYPE_STORAGE_BUFFER), @as(i64, abi.c.KE_GPU_BINDING_TYPE_STORAGE_BUFFER));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BINDING_TYPE_STORAGE_TEXTURE), @as(i64, abi.c.KE_GPU_BINDING_TYPE_STORAGE_TEXTURE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER), @as(i64, abi.c.KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE), @as(i64, abi.c.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_SHADER_LANG_WGSL), @as(i64, abi.c.KE_GPU_SHADER_LANG_WGSL));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_SHADER_LANG_SPIRV), @as(i64, abi.c.KE_GPU_SHADER_LANG_SPIRV));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_SHADER_LANG_MSL), @as(i64, abi.c.KE_GPU_SHADER_LANG_MSL));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_SHADER_LANG_DXIL), @as(i64, abi.c.KE_GPU_SHADER_LANG_DXIL));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_BINDING_HINT_DEPTH), @as(i64, abi.c.KE_RENDER_BINDING_HINT_DEPTH));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET), @as(i64, abi.c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_GPU_TEXTURE_ASPECT_COLOR), @as(i128, abi.c.KE_GPU_TEXTURE_ASPECT_COLOR));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_TEXTURE_ASPECT_DEPTH), @as(i128, abi.c.KE_GPU_TEXTURE_ASPECT_DEPTH));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_TEXTURE_ASPECT_STENCIL), @as(i128, abi.c.KE_GPU_TEXTURE_ASPECT_STENCIL));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_TEXTURE_USAGE_COPY_SRC), @as(i128, abi.c.KE_GPU_TEXTURE_USAGE_COPY_SRC));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_TEXTURE_USAGE_COPY_DST), @as(i128, abi.c.KE_GPU_TEXTURE_USAGE_COPY_DST));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_TEXTURE_USAGE_SAMPLED), @as(i128, abi.c.KE_GPU_TEXTURE_USAGE_SAMPLED));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_TEXTURE_USAGE_STORAGE), @as(i128, abi.c.KE_GPU_TEXTURE_USAGE_STORAGE));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH), @as(i128, abi.c.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH), @as(i128, abi.c.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_BUFFER_USAGE_MAP_READ), @as(i128, abi.c.KE_GPU_BUFFER_USAGE_MAP_READ));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_BUFFER_USAGE_MAP_WRITE), @as(i128, abi.c.KE_GPU_BUFFER_USAGE_MAP_WRITE));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_BUFFER_USAGE_COPY_SRC), @as(i128, abi.c.KE_GPU_BUFFER_USAGE_COPY_SRC));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_BUFFER_USAGE_COPY_DST), @as(i128, abi.c.KE_GPU_BUFFER_USAGE_COPY_DST));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_BUFFER_USAGE_INDEX), @as(i128, abi.c.KE_GPU_BUFFER_USAGE_INDEX));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_BUFFER_USAGE_VERTEX), @as(i128, abi.c.KE_GPU_BUFFER_USAGE_VERTEX));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_BUFFER_USAGE_UNIFORM), @as(i128, abi.c.KE_GPU_BUFFER_USAGE_UNIFORM));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_BUFFER_USAGE_STORAGE), @as(i128, abi.c.KE_GPU_BUFFER_USAGE_STORAGE));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_BUFFER_USAGE_INDIRECT), @as(i128, abi.c.KE_GPU_BUFFER_USAGE_INDIRECT));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_SHADER_STAGE_VERTEX), @as(i128, abi.c.KE_GPU_SHADER_STAGE_VERTEX));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_SHADER_STAGE_FRAGMENT), @as(i128, abi.c.KE_GPU_SHADER_STAGE_FRAGMENT));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_SHADER_STAGE_COMPUTE), @as(i128, abi.c.KE_GPU_SHADER_STAGE_COMPUTE));
    try std.testing.expectEqual(@as(i128, c.KE_GPU_INVALID_HANDLE), @as(i128, abi.c.KE_GPU_INVALID_HANDLE));
    try std.testing.expectEqual(@as(i128, c.KE_RENDER_BINDING_INVALID), @as(i128, abi.c.KE_RENDER_BINDING_INVALID));
}

extern const layout_values: [299]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_ndc_convention),
        @offsetOf(abi.c.ke_ndc_convention, "z_zero_to_one"),
        @offsetOf(abi.c.ke_ndc_convention, "y_flip"),
        @sizeOf(abi.c.ke_gpu_clear_value),
        @sizeOf(abi.c.ke_gpu_capabilities),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_texture_dimension_2d"),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_texture_array_layers"),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_bind_groups"),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_vertex_attributes"),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_vertex_buffers"),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_uniform_buffer_size"),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_storage_buffer_size"),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_compute_workgroup_size_x"),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_compute_workgroup_size_y"),
        @offsetOf(abi.c.ke_gpu_capabilities, "max_compute_workgroup_size_z"),
        @offsetOf(abi.c.ke_gpu_capabilities, "supports_bindless"),
        @offsetOf(abi.c.ke_gpu_capabilities, "supports_mesh_shaders"),
        @offsetOf(abi.c.ke_gpu_capabilities, "supports_ray_tracing"),
        @offsetOf(abi.c.ke_gpu_capabilities, "copy_bytes_per_row_alignment"),
        @sizeOf(abi.c.ke_gpu_buffer_params),
        @offsetOf(abi.c.ke_gpu_buffer_params, "label"),
        @offsetOf(abi.c.ke_gpu_buffer_params, "initial_data"),
        @offsetOf(abi.c.ke_gpu_buffer_params, "size"),
        @offsetOf(abi.c.ke_gpu_buffer_params, "usage"),
        @offsetOf(abi.c.ke_gpu_buffer_params, "mapped_at_creation"),
        @sizeOf(abi.c.ke_gpu_texture_params),
        @offsetOf(abi.c.ke_gpu_texture_params, "label"),
        @offsetOf(abi.c.ke_gpu_texture_params, "width"),
        @offsetOf(abi.c.ke_gpu_texture_params, "height"),
        @offsetOf(abi.c.ke_gpu_texture_params, "depth_or_array_layers"),
        @offsetOf(abi.c.ke_gpu_texture_params, "format"),
        @offsetOf(abi.c.ke_gpu_texture_params, "dimension"),
        @offsetOf(abi.c.ke_gpu_texture_params, "usage"),
        @offsetOf(abi.c.ke_gpu_texture_params, "mip_level_count"),
        @offsetOf(abi.c.ke_gpu_texture_params, "sample_count"),
        @offsetOf(abi.c.ke_gpu_texture_params, "initial_data"),
        @offsetOf(abi.c.ke_gpu_texture_params, "initial_data_size"),
        @sizeOf(abi.c.ke_gpu_texture_view_params),
        @offsetOf(abi.c.ke_gpu_texture_view_params, "label"),
        @offsetOf(abi.c.ke_gpu_texture_view_params, "format"),
        @offsetOf(abi.c.ke_gpu_texture_view_params, "dimension"),
        @offsetOf(abi.c.ke_gpu_texture_view_params, "aspect"),
        @offsetOf(abi.c.ke_gpu_texture_view_params, "base_mip_level"),
        @offsetOf(abi.c.ke_gpu_texture_view_params, "mip_level_count"),
        @offsetOf(abi.c.ke_gpu_texture_view_params, "base_array_layer"),
        @offsetOf(abi.c.ke_gpu_texture_view_params, "array_layer_count"),
        @sizeOf(abi.c.ke_gpu_sampler_params),
        @offsetOf(abi.c.ke_gpu_sampler_params, "label"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "min_filter"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "mag_filter"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "mipmap_filter"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "address_mode_u"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "address_mode_v"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "address_mode_w"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "lod_min_clamp"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "lod_max_clamp"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "compare"),
        @offsetOf(abi.c.ke_gpu_sampler_params, "max_anisotropy"),
        @sizeOf(abi.c.ke_gpu_shader_module_params),
        @offsetOf(abi.c.ke_gpu_shader_module_params, "label"),
        @offsetOf(abi.c.ke_gpu_shader_module_params, "code"),
        @offsetOf(abi.c.ke_gpu_shader_module_params, "byte_size"),
        @sizeOf(abi.c.ke_gpu_vertex_attribute),
        @offsetOf(abi.c.ke_gpu_vertex_attribute, "shader_location"),
        @offsetOf(abi.c.ke_gpu_vertex_attribute, "format"),
        @offsetOf(abi.c.ke_gpu_vertex_attribute, "offset"),
        @sizeOf(abi.c.ke_gpu_vertex_buffer_layout),
        @offsetOf(abi.c.ke_gpu_vertex_buffer_layout, "stride"),
        @offsetOf(abi.c.ke_gpu_vertex_buffer_layout, "step_mode"),
        @offsetOf(abi.c.ke_gpu_vertex_buffer_layout, "attribute_count"),
        @offsetOf(abi.c.ke_gpu_vertex_buffer_layout, "attributes"),
        @sizeOf(abi.c.ke_gpu_blend_state),
        @offsetOf(abi.c.ke_gpu_blend_state, "blend_enabled"),
        @offsetOf(abi.c.ke_gpu_blend_state, "src_color"),
        @offsetOf(abi.c.ke_gpu_blend_state, "dst_color"),
        @offsetOf(abi.c.ke_gpu_blend_state, "color_op"),
        @offsetOf(abi.c.ke_gpu_blend_state, "src_alpha"),
        @offsetOf(abi.c.ke_gpu_blend_state, "dst_alpha"),
        @offsetOf(abi.c.ke_gpu_blend_state, "alpha_op"),
        @offsetOf(abi.c.ke_gpu_blend_state, "write_mask"),
        @sizeOf(abi.c.ke_gpu_depth_stencil_state),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "depth_test_enabled"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "depth_write_enabled"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "depth_compare"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_test_enabled"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_front_fail"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_front_depth_fail"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_front_pass"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_front_compare"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_back_fail"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_back_depth_fail"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_back_pass"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_back_compare"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_read_mask"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_state, "stencil_write_mask"),
        @sizeOf(abi.c.ke_gpu_bind_group_layout_entry),
        @offsetOf(abi.c.ke_gpu_bind_group_layout_entry, "binding"),
        @offsetOf(abi.c.ke_gpu_bind_group_layout_entry, "visibility"),
        @offsetOf(abi.c.ke_gpu_bind_group_layout_entry, "type"),
        @offsetOf(abi.c.ke_gpu_bind_group_layout_entry, "has_dynamic_offset"),
        @offsetOf(abi.c.ke_gpu_bind_group_layout_entry, "view_dimension"),
        @sizeOf(abi.c.ke_gpu_bind_group_layout_params),
        @offsetOf(abi.c.ke_gpu_bind_group_layout_params, "label"),
        @offsetOf(abi.c.ke_gpu_bind_group_layout_params, "entry_count"),
        @offsetOf(abi.c.ke_gpu_bind_group_layout_params, "entries"),
        @sizeOf(abi.c.ke_gpu_bind_group_entry),
        @offsetOf(abi.c.ke_gpu_bind_group_entry, "binding"),
        @offsetOf(abi.c.ke_gpu_bind_group_entry, "type"),
        @offsetOf(abi.c.ke_gpu_bind_group_entry, "buffer"),
        @offsetOf(abi.c.ke_gpu_bind_group_entry, "buffer_offset"),
        @offsetOf(abi.c.ke_gpu_bind_group_entry, "buffer_size"),
        @offsetOf(abi.c.ke_gpu_bind_group_entry, "texture_view"),
        @offsetOf(abi.c.ke_gpu_bind_group_entry, "sampler"),
        @sizeOf(abi.c.ke_gpu_bind_group_params),
        @offsetOf(abi.c.ke_gpu_bind_group_params, "label"),
        @offsetOf(abi.c.ke_gpu_bind_group_params, "layout"),
        @offsetOf(abi.c.ke_gpu_bind_group_params, "entry_count"),
        @offsetOf(abi.c.ke_gpu_bind_group_params, "entries"),
        @sizeOf(abi.c.ke_gpu_render_pipeline_params),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "label"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "vertex_module"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "fragment_module"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "vertex_entry"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "fragment_entry"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "primitive_topology"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "cull_mode"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "front_face"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "vertex_buffer_count"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "vertex_buffers"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "blend_state"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "depth_stencil"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "bind_group_layouts"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "bind_group_layout_count"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "alpha_to_coverage_enabled"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "color_target_formats"),
        @offsetOf(abi.c.ke_gpu_render_pipeline_params, "color_target_count"),
        @sizeOf(abi.c.ke_gpu_compute_pipeline_params),
        @offsetOf(abi.c.ke_gpu_compute_pipeline_params, "label"),
        @offsetOf(abi.c.ke_gpu_compute_pipeline_params, "compute_module"),
        @offsetOf(abi.c.ke_gpu_compute_pipeline_params, "compute_entry"),
        @offsetOf(abi.c.ke_gpu_compute_pipeline_params, "bind_group_layouts"),
        @offsetOf(abi.c.ke_gpu_compute_pipeline_params, "bind_group_layout_count"),
        @sizeOf(abi.c.ke_gpu_color_attachment),
        @offsetOf(abi.c.ke_gpu_color_attachment, "view"),
        @offsetOf(abi.c.ke_gpu_color_attachment, "load_op"),
        @offsetOf(abi.c.ke_gpu_color_attachment, "store_op"),
        @offsetOf(abi.c.ke_gpu_color_attachment, "clear_value"),
        @sizeOf(abi.c.ke_gpu_depth_stencil_attachment),
        @offsetOf(abi.c.ke_gpu_depth_stencil_attachment, "view"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_attachment, "depth_load_op"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_attachment, "depth_store_op"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_attachment, "stencil_store_op"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_attachment, "clear_depth"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_attachment, "clear_stencil"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_attachment, "depth_read_only"),
        @offsetOf(abi.c.ke_gpu_depth_stencil_attachment, "stencil_read_only"),
        @sizeOf(abi.c.ke_gpu_render_pass_params),
        @offsetOf(abi.c.ke_gpu_render_pass_params, "label"),
        @offsetOf(abi.c.ke_gpu_render_pass_params, "color_attachments"),
        @offsetOf(abi.c.ke_gpu_render_pass_params, "color_attachment_count"),
        @offsetOf(abi.c.ke_gpu_render_pass_params, "depth_stencil_attachment"),
        @sizeOf(abi.c.ke_gpu_command_encoder_params),
        @offsetOf(abi.c.ke_gpu_command_encoder_params, "label"),
        @sizeOf(abi.c.ke_gpu_compute_pass_params),
        @offsetOf(abi.c.ke_gpu_compute_pass_params, "label"),
        @sizeOf(abi.c.ke_gpu_command_buffer),
        @offsetOf(abi.c.ke_gpu_command_buffer, "handle"),
        @sizeOf(abi.c.ke_render_binding_hint),
        @offsetOf(abi.c.ke_render_binding_hint, "name"),
        @offsetOf(abi.c.ke_render_binding_hint, "flags"),
        @sizeOf(abi.c.ke_render_shader_binding),
        @offsetOf(abi.c.ke_render_shader_binding, "name"),
        @offsetOf(abi.c.ke_render_shader_binding, "buffer"),
        @offsetOf(abi.c.ke_render_shader_binding, "buffer_offset"),
        @offsetOf(abi.c.ke_render_shader_binding, "buffer_size"),
        @offsetOf(abi.c.ke_render_shader_binding, "texture_view"),
        @offsetOf(abi.c.ke_render_shader_binding, "sampler"),
        @sizeOf(abi.c.ke_render_shader_layout_params),
        @offsetOf(abi.c.ke_render_shader_layout_params, "shader"),
        @offsetOf(abi.c.ke_render_shader_layout_params, "stages"),
        @offsetOf(abi.c.ke_render_shader_layout_params, "hints"),
        @offsetOf(abi.c.ke_render_shader_layout_params, "hint_count"),
        @sizeOf(abi.c.ke_render_material_data),
        @offsetOf(abi.c.ke_render_material_data, "base_color"),
        @offsetOf(abi.c.ke_render_material_data, "metallic"),
        @offsetOf(abi.c.ke_render_material_data, "roughness"),
        @offsetOf(abi.c.ke_render_material_data, "alpha_cutoff"),
        @offsetOf(abi.c.ke_render_material_data, "ior"),
        @offsetOf(abi.c.ke_render_material_data, "distortion_strength"),
        @offsetOf(abi.c.ke_render_material_data, "albedo"),
        @offsetOf(abi.c.ke_render_material_data, "normal_map"),
        @sizeOf(abi.c.ke_gpu_command_encoder_handle),
        @offsetOf(abi.c.ke_gpu_command_encoder_handle, "ref"),
        @offsetOf(abi.c.ke_gpu_command_encoder_handle, "destroy"),
        @sizeOf(abi.c.ke_gpu_command_buffer_handle),
        @offsetOf(abi.c.ke_gpu_command_buffer_handle, "ref"),
        @offsetOf(abi.c.ke_gpu_command_buffer_handle, "destroy"),
        @sizeOf(abi.c.ke_gpu_device),
        @offsetOf(abi.c.ke_gpu_device, "handle"),
        @offsetOf(abi.c.ke_gpu_device, "get_default_queue"),
        @offsetOf(abi.c.ke_gpu_device, "queue_submit"),
        @offsetOf(abi.c.ke_gpu_device, "queue_poll"),
        @offsetOf(abi.c.ke_gpu_device, "queue_wait_idle"),
        @offsetOf(abi.c.ke_gpu_device, "create_buffer"),
        @offsetOf(abi.c.ke_gpu_device, "create_texture"),
        @offsetOf(abi.c.ke_gpu_device, "create_texture_view"),
        @offsetOf(abi.c.ke_gpu_device, "create_sampler"),
        @offsetOf(abi.c.ke_gpu_device, "create_shader_module"),
        @offsetOf(abi.c.ke_gpu_device, "create_render_pipeline"),
        @offsetOf(abi.c.ke_gpu_device, "create_compute_pipeline"),
        @offsetOf(abi.c.ke_gpu_device, "create_bind_group_layout"),
        @offsetOf(abi.c.ke_gpu_device, "create_bind_group"),
        @offsetOf(abi.c.ke_gpu_device, "destroy_buffer"),
        @offsetOf(abi.c.ke_gpu_device, "destroy_texture"),
        @offsetOf(abi.c.ke_gpu_device, "destroy_texture_view"),
        @offsetOf(abi.c.ke_gpu_device, "destroy_sampler"),
        @offsetOf(abi.c.ke_gpu_device, "destroy_shader_module"),
        @offsetOf(abi.c.ke_gpu_device, "destroy_pipeline"),
        @offsetOf(abi.c.ke_gpu_device, "destroy_bind_group_layout"),
        @offsetOf(abi.c.ke_gpu_device, "destroy_bind_group"),
        @offsetOf(abi.c.ke_gpu_device, "create_command_encoder"),
        @offsetOf(abi.c.ke_gpu_device, "write_buffer"),
        @offsetOf(abi.c.ke_gpu_device, "map_buffer"),
        @offsetOf(abi.c.ke_gpu_device, "map_buffer_write"),
        @offsetOf(abi.c.ke_gpu_device, "unmap_buffer"),
        @offsetOf(abi.c.ke_gpu_device, "get_capabilities"),
        @offsetOf(abi.c.ke_gpu_device, "query_extension"),
        @offsetOf(abi.c.ke_gpu_device, "shader_language"),
        @offsetOf(abi.c.ke_gpu_device, "get_ndc_convention"),
        @offsetOf(abi.c.ke_gpu_device, "create_render_pipeline_async"),
        @offsetOf(abi.c.ke_gpu_device, "flush_pipeline_compiles"),
        @offsetOf(abi.c.ke_gpu_device, "map_buffer_read"),
        @offsetOf(abi.c.ke_gpu_device, "destroy_compute_pipeline"),
        @sizeOf(abi.c.ke_gpu_device_handle),
        @offsetOf(abi.c.ke_gpu_device_handle, "ref"),
        @offsetOf(abi.c.ke_gpu_device_handle, "destroy"),
        @sizeOf(abi.c.ke_gpu_render_pass),
        @offsetOf(abi.c.ke_gpu_render_pass, "handle"),
        @offsetOf(abi.c.ke_gpu_render_pass, "set_pipeline"),
        @offsetOf(abi.c.ke_gpu_render_pass, "set_bind_group"),
        @offsetOf(abi.c.ke_gpu_render_pass, "set_vertex_buffer"),
        @offsetOf(abi.c.ke_gpu_render_pass, "set_index_buffer"),
        @offsetOf(abi.c.ke_gpu_render_pass, "set_viewport"),
        @offsetOf(abi.c.ke_gpu_render_pass, "set_scissor"),
        @offsetOf(abi.c.ke_gpu_render_pass, "draw"),
        @offsetOf(abi.c.ke_gpu_render_pass, "draw_indexed"),
        @offsetOf(abi.c.ke_gpu_render_pass, "draw_indirect"),
        @offsetOf(abi.c.ke_gpu_render_pass, "end"),
        @offsetOf(abi.c.ke_gpu_render_pass, "push_debug_group"),
        @offsetOf(abi.c.ke_gpu_render_pass, "pop_debug_group"),
        @offsetOf(abi.c.ke_gpu_render_pass, "insert_debug_marker"),
        @sizeOf(abi.c.ke_gpu_compute_pass),
        @offsetOf(abi.c.ke_gpu_compute_pass, "handle"),
        @offsetOf(abi.c.ke_gpu_compute_pass, "set_pipeline"),
        @offsetOf(abi.c.ke_gpu_compute_pass, "set_bind_group"),
        @offsetOf(abi.c.ke_gpu_compute_pass, "dispatch"),
        @offsetOf(abi.c.ke_gpu_compute_pass, "dispatch_indirect"),
        @offsetOf(abi.c.ke_gpu_compute_pass, "end"),
        @offsetOf(abi.c.ke_gpu_compute_pass, "push_debug_group"),
        @offsetOf(abi.c.ke_gpu_compute_pass, "pop_debug_group"),
        @offsetOf(abi.c.ke_gpu_compute_pass, "insert_debug_marker"),
        @sizeOf(abi.c.ke_gpu_command_encoder),
        @offsetOf(abi.c.ke_gpu_command_encoder, "handle"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "begin_render_pass"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "begin_compute_pass"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "copy_buffer_to_buffer"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "copy_buffer_to_texture"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "copy_texture_to_texture"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "finish"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "copy_texture_to_buffer"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "push_debug_group"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "pop_debug_group"),
        @offsetOf(abi.c.ke_gpu_command_encoder, "insert_debug_marker"),
        @sizeOf(abi.c.ke_gpu_render_target),
        @offsetOf(abi.c.ke_gpu_render_target, "handle"),
        @offsetOf(abi.c.ke_gpu_render_target, "acquire"),
        @offsetOf(abi.c.ke_gpu_render_target, "present"),
        @offsetOf(abi.c.ke_gpu_render_target, "size"),
        @offsetOf(abi.c.ke_gpu_render_target, "format"),
        @sizeOf(abi.c.ke_gpu_render_target_handle),
        @offsetOf(abi.c.ke_gpu_render_target_handle, "ref"),
        @offsetOf(abi.c.ke_gpu_render_target_handle, "destroy"),
        @sizeOf(abi.c.ke_render_resource_binder),
        @offsetOf(abi.c.ke_render_resource_binder, "handle"),
        @offsetOf(abi.c.ke_render_resource_binder, "provide"),
        @offsetOf(abi.c.ke_render_resource_binder, "create_shader_layout"),
        @offsetOf(abi.c.ke_render_resource_binder, "destroy_shader_layout"),
        @offsetOf(abi.c.ke_render_resource_binder, "pipeline_layouts"),
        @offsetOf(abi.c.ke_render_resource_binder, "create_set"),
        @offsetOf(abi.c.ke_render_resource_binder, "destroy_set"),
        @offsetOf(abi.c.ke_render_resource_binder, "bind_render_set"),
        @offsetOf(abi.c.ke_render_resource_binder, "bind_compute_set"),
        @offsetOf(abi.c.ke_render_resource_binder, "create_material"),
        @offsetOf(abi.c.ke_render_resource_binder, "destroy_material"),
        @offsetOf(abi.c.ke_render_resource_binder, "bind_material"),
        @sizeOf(abi.c.ke_render_resource_binder_handle),
        @offsetOf(abi.c.ke_render_resource_binder_handle, "ref"),
        @offsetOf(abi.c.ke_render_resource_binder_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

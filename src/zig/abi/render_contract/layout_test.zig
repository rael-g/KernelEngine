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
    try expectSameLayout(abi.c.ke_render_pass_ctx, translated("ke_render_pass_ctx"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
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
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_UI_QUAD, abi.c.KE_COMPONENT_NAME_UI_QUAD);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_LABEL, abi.c.KE_COMPONENT_NAME_LABEL);
}

extern const layout_values: [11]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
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

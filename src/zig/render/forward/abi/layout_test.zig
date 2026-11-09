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
    try expectSameLayout(abi.c.ke_render_forward_config, translated("ke_render_forward_config"));
    try expectSameLayout(abi.c.ke_render_forward_handle, translated("ke_render_forward_handle"));
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
    if (@hasDecl(c, "ke_log_callback")) try expectSameLayout(abi.c.ke_log_callback, c.ke_log_callback);
    if (@hasDecl(c, "ke_module_id")) try expectSameLayout(abi.c.ke_module_id, c.ke_module_id);
    if (@hasDecl(c, "ke_module_load_fn")) try expectSameLayout(abi.c.ke_module_load_fn, c.ke_module_load_fn);
    if (@hasDecl(c, "ke_module_unload_fn")) try expectSameLayout(abi.c.ke_module_unload_fn, c.ke_module_unload_fn);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_render_chain_link")) try expectSameLayout(abi.c.ke_render_chain_link, c.ke_render_chain_link);
    if (@hasDecl(c, "ke_render_material_binding")) try expectSameLayout(abi.c.ke_render_material_binding, c.ke_render_material_binding);
    if (@hasDecl(c, "ke_render_resource_set")) try expectSameLayout(abi.c.ke_render_resource_set, c.ke_render_resource_set);
    if (@hasDecl(c, "ke_render_shader_layout")) try expectSameLayout(abi.c.ke_render_shader_layout, c.ke_render_shader_layout);
    if (@hasDecl(c, "ke_system_execute_fn")) try expectSameLayout(abi.c.ke_system_execute_fn, c.ke_system_execute_fn);
    if (@hasDecl(c, "ke_system_id")) try expectSameLayout(abi.c.ke_system_id, c.ke_system_id);
}

extern const layout_values: [8]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_render_forward_config),
        @offsetOf(abi.c.ke_render_forward_config, "ibl_enabled"),
        @offsetOf(abi.c.ke_render_forward_config, "shadow"),
        @offsetOf(abi.c.ke_render_forward_config, "clusters"),
        @sizeOf(abi.c.ke_render_forward_handle),
        @offsetOf(abi.c.ke_render_forward_handle, "ref"),
        @offsetOf(abi.c.ke_render_forward_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

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
    try expectSameLayout(abi.c.ke_render_graph_texture_desc, translated("ke_render_graph_texture_desc"));
    try expectSameLayout(abi.c.ke_render_graph_buffer_desc, translated("ke_render_graph_buffer_desc"));
    try expectSameLayout(abi.c.ke_render_graph_use, translated("ke_render_graph_use"));
    try expectSameLayout(abi.c.ke_render_graph_pass_desc, translated("ke_render_graph_pass_desc"));
    try expectSameLayout(abi.c.ke_render_graph_ctx, translated("ke_render_graph_ctx"));
    try expectSameLayout(abi.c.ke_render_graph, translated("ke_render_graph"));
    try expectSameLayout(abi.c.ke_render_graph_handle, translated("ke_render_graph_handle"));
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
    if (@hasDecl(c, "ke_render_graph_condition_fn")) try expectSameLayout(abi.c.ke_render_graph_condition_fn, c.ke_render_graph_condition_fn);
    if (@hasDecl(c, "ke_render_graph_export")) try expectSameLayout(abi.c.ke_render_graph_export, c.ke_render_graph_export);
    if (@hasDecl(c, "ke_render_graph_pass")) try expectSameLayout(abi.c.ke_render_graph_pass, c.ke_render_graph_pass);
    if (@hasDecl(c, "ke_render_graph_readback_fn")) try expectSameLayout(abi.c.ke_render_graph_readback_fn, c.ke_render_graph_readback_fn);
    if (@hasDecl(c, "ke_render_graph_record_fn")) try expectSameLayout(abi.c.ke_render_graph_record_fn, c.ke_render_graph_record_fn);
    if (@hasDecl(c, "ke_render_graph_resource")) try expectSameLayout(abi.c.ke_render_graph_resource, c.ke_render_graph_resource);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_RESOURCE_TEXTURE), @as(i64, abi.c.KE_RENDER_GRAPH_RESOURCE_TEXTURE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_RESOURCE_BUFFER), @as(i64, abi.c.KE_RENDER_GRAPH_RESOURCE_BUFFER));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_RESOURCE_TOKEN), @as(i64, abi.c.KE_RENDER_GRAPH_RESOURCE_TOKEN));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_RESOURCE_ACCELERATION_STRUCTURE), @as(i64, abi.c.KE_RENDER_GRAPH_RESOURCE_ACCELERATION_STRUCTURE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_SIZE_ABSOLUTE), @as(i64, abi.c.KE_RENDER_GRAPH_SIZE_ABSOLUTE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_SIZE_OUTPUT_RELATIVE), @as(i64, abi.c.KE_RENDER_GRAPH_SIZE_OUTPUT_RELATIVE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_SIZE_RESOURCE_RELATIVE), @as(i64, abi.c.KE_RENDER_GRAPH_SIZE_RESOURCE_RELATIVE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_SAMPLED), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_SAMPLED));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_STORAGE_READ), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_STORAGE_READ));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_STORAGE_WRITE), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_STORAGE_WRITE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_DEPTH_READ), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_DEPTH_READ));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_DEPTH_WRITE), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_DEPTH_WRITE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_INPUT_ATTACHMENT), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_INPUT_ATTACHMENT));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_RESOLVE), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_RESOLVE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_COPY_SRC), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_COPY_SRC));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_COPY_DST), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_COPY_DST));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_VERTEX), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_VERTEX));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_INDEX), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_INDEX));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_INDIRECT), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_INDIRECT));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_UNIFORM), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_UNIFORM));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_PRESENT), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_PRESENT));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_READBACK), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_READBACK));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_AS_BUILD), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_AS_BUILD));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_AS_READ), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_AS_READ));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_TOKEN_READ), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_TOKEN_READ));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_USAGE_TOKEN_WRITE), @as(i64, abi.c.KE_RENDER_GRAPH_USAGE_TOKEN_WRITE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_LOAD_KEEP), @as(i64, abi.c.KE_RENDER_GRAPH_LOAD_KEEP));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_LOAD_CLEAR), @as(i64, abi.c.KE_RENDER_GRAPH_LOAD_CLEAR));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_LOAD_DONT_CARE), @as(i64, abi.c.KE_RENDER_GRAPH_LOAD_DONT_CARE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_PASS_RASTER), @as(i64, abi.c.KE_RENDER_GRAPH_PASS_RASTER));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_PASS_COMPUTE), @as(i64, abi.c.KE_RENDER_GRAPH_PASS_COMPUTE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_PASS_COPY), @as(i64, abi.c.KE_RENDER_GRAPH_PASS_COPY));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_QUEUE_GRAPHICS), @as(i64, abi.c.KE_RENDER_GRAPH_QUEUE_GRAPHICS));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_QUEUE_ASYNC_COMPUTE), @as(i64, abi.c.KE_RENDER_GRAPH_QUEUE_ASYNC_COMPUTE));
    try std.testing.expectEqual(@as(i64, c.KE_RENDER_GRAPH_QUEUE_TRANSFER), @as(i64, abi.c.KE_RENDER_GRAPH_QUEUE_TRANSFER));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_RENDER_GRAPH_RESOURCE_INVALID), @as(i128, abi.c.KE_RENDER_GRAPH_RESOURCE_INVALID));
}

extern const layout_values: [67]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_render_graph_texture_desc),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "name"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "format"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "size_class"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "width"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "height"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "scale_x"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "scale_y"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "relative_to"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "mip_levels"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "array_layers"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "samples"),
        @offsetOf(abi.c.ke_render_graph_texture_desc, "generate_mips"),
        @sizeOf(abi.c.ke_render_graph_buffer_desc),
        @offsetOf(abi.c.ke_render_graph_buffer_desc, "name"),
        @offsetOf(abi.c.ke_render_graph_buffer_desc, "size"),
        @sizeOf(abi.c.ke_render_graph_use),
        @offsetOf(abi.c.ke_render_graph_use, "resource"),
        @offsetOf(abi.c.ke_render_graph_use, "usage"),
        @offsetOf(abi.c.ke_render_graph_use, "base_mip"),
        @offsetOf(abi.c.ke_render_graph_use, "mip_count"),
        @offsetOf(abi.c.ke_render_graph_use, "base_layer"),
        @offsetOf(abi.c.ke_render_graph_use, "layer_count"),
        @offsetOf(abi.c.ke_render_graph_use, "view_format"),
        @offsetOf(abi.c.ke_render_graph_use, "load"),
        @offsetOf(abi.c.ke_render_graph_use, "clear_color"),
        @offsetOf(abi.c.ke_render_graph_use, "clear_depth"),
        @offsetOf(abi.c.ke_render_graph_use, "clear_stencil"),
        @sizeOf(abi.c.ke_render_graph_pass_desc),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "name"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "type"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "queue"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "injection_point"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "side_effect"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "uses"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "use_count"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "record"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "condition"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "readback"),
        @offsetOf(abi.c.ke_render_graph_pass_desc, "user"),
        @sizeOf(abi.c.ke_render_graph_ctx),
        @offsetOf(abi.c.ke_render_graph_ctx, "handle"),
        @offsetOf(abi.c.ke_render_graph_ctx, "encoder"),
        @offsetOf(abi.c.ke_render_graph_ctx, "render_pass"),
        @offsetOf(abi.c.ke_render_graph_ctx, "compute_pass"),
        @offsetOf(abi.c.ke_render_graph_ctx, "texture"),
        @offsetOf(abi.c.ke_render_graph_ctx, "texture_view"),
        @offsetOf(abi.c.ke_render_graph_ctx, "buffer"),
        @offsetOf(abi.c.ke_render_graph_ctx, "buffer_size"),
        @sizeOf(abi.c.ke_render_graph),
        @offsetOf(abi.c.ke_render_graph, "handle"),
        @offsetOf(abi.c.ke_render_graph, "begin_frame"),
        @offsetOf(abi.c.ke_render_graph, "create_texture"),
        @offsetOf(abi.c.ke_render_graph, "create_buffer"),
        @offsetOf(abi.c.ke_render_graph, "create_token"),
        @offsetOf(abi.c.ke_render_graph, "import_texture"),
        @offsetOf(abi.c.ke_render_graph, "import_buffer"),
        @offsetOf(abi.c.ke_render_graph, "export_resource"),
        @offsetOf(abi.c.ke_render_graph, "import_export"),
        @offsetOf(abi.c.ke_render_graph, "release_export"),
        @offsetOf(abi.c.ke_render_graph, "add_pass"),
        @offsetOf(abi.c.ke_render_graph, "compile"),
        @offsetOf(abi.c.ke_render_graph, "execute"),
        @sizeOf(abi.c.ke_render_graph_handle),
        @offsetOf(abi.c.ke_render_graph_handle, "ref"),
        @offsetOf(abi.c.ke_render_graph_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

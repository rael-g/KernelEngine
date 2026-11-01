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
    try expectSameLayout(abi.c.ke_gpu_device_webgpu_params, translated("ke_gpu_device_webgpu_params"));
    try expectSameLayout(abi.c.ke_gpu_render_target_webgpu_window_params, translated("ke_gpu_render_target_webgpu_window_params"));
    if (@hasDecl(c, "ke_configuration_change_func")) try expectSameLayout(abi.c.ke_configuration_change_func, c.ke_configuration_change_func);
    if (@hasDecl(c, "ke_configuration_subscription")) try expectSameLayout(abi.c.ke_configuration_subscription, c.ke_configuration_subscription);
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
    if (@hasDecl(c, "ke_log_callback")) try expectSameLayout(abi.c.ke_log_callback, c.ke_log_callback);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_GPU_PRESENT_MODE_FIFO), @as(i64, abi.c.KE_GPU_PRESENT_MODE_FIFO));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_PRESENT_MODE_MAILBOX), @as(i64, abi.c.KE_GPU_PRESENT_MODE_MAILBOX));
    try std.testing.expectEqual(@as(i64, c.KE_GPU_PRESENT_MODE_IMMEDIATE), @as(i64, abi.c.KE_GPU_PRESENT_MODE_IMMEDIATE));
}

extern const layout_values: [11]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_gpu_device_webgpu_params),
        @offsetOf(abi.c.ke_gpu_device_webgpu_params, "enable_validation"),
        @offsetOf(abi.c.ke_gpu_device_webgpu_params, "task_pool"),
        @offsetOf(abi.c.ke_gpu_device_webgpu_params, "debug_labels"),
        @offsetOf(abi.c.ke_gpu_device_webgpu_params, "configuration"),
        @sizeOf(abi.c.ke_gpu_render_target_webgpu_window_params),
        @offsetOf(abi.c.ke_gpu_render_target_webgpu_window_params, "device"),
        @offsetOf(abi.c.ke_gpu_render_target_webgpu_window_params, "window"),
        @offsetOf(abi.c.ke_gpu_render_target_webgpu_window_params, "present_mode"),
        @offsetOf(abi.c.ke_gpu_render_target_webgpu_window_params, "configuration"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}

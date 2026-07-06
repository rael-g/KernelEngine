const std = @import("std");
const cimport = @import("cimport.zig");
const c = cimport.c;

// Skybox — extracted as a §9.8 decomposition module. Unlike shadow, it has no
// runtime system of its own: it draws inside the forward pass's render pass
// (clear → opaque meshes → skybox, depth LEQUAL, no write, filling only the
// background), sharing set 0 (frame_bgl) with the forward/magenta pipelines.
// So this module exposes setup() + draw(rp, ...) instead of setup() + a
// system() callback — the shape a feature module takes follows how it
// actually composes with the pass graph, not a fixed template.

const skybox_vs_wgsl = @embedFile("skybox.vs.wgsl");
const skybox_fs_wgsl = @embedFile("skybox.fs.wgsl");

// Unit cube positions (8 corners) + indices.
const sky_verts = [_]f32{
    -1, -1, -1, 1, -1, -1, 1, 1, -1, -1, 1, -1,
    -1, -1, 1,  1, -1, 1,  1, 1, 1,  -1, 1, 1,
};
const sky_idx = [_]u16{
    0, 1, 2, 0, 2, 3, // -Z
    4, 6, 5, 4, 7, 6, // +Z
    0, 4, 5, 0, 5, 1, // -Y
    3, 2, 6, 3, 6, 7, // +Y
    0, 3, 7, 0, 7, 4, // -X
    1, 5, 6, 1, 6, 2, // +X
};

pub const SkyboxModule = struct {
    pipeline: c.ke_gpu_pipeline = c.KE_GPU_INVALID_HANDLE,
    vbo: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    ibo: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
};

// frame_bgl is borrowed — the shared set-0 layout the forward/magenta
// pipelines also use, owned by the parent module (rebuilt on env change).
pub fn setup(sm: *SkyboxModule, dev: *c.ke_gpu_device, frame_bgl: c.ke_gpu_bind_group_layout, out_error: [*c][*c]c.ke_error) bool {
    const sky_vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(skybox_vs_wgsl),
        .byte_size = skybox_vs_wgsl.len,
        .entry_point = "skybox.vs",
    }, out_error);
    if (sky_vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sky_vs);
    const sky_fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(skybox_fs_wgsl),
        .byte_size = skybox_fs_wgsl.len,
        .entry_point = "skybox.fs",
    }, out_error);
    if (sky_fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sky_fs);

    const sky_attr = c.ke_gpu_vertex_attribute{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 };
    const sky_vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = 3 * @sizeOf(f32),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 1,
        .attributes = &sky_attr,
    };
    var skp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    skp.vertex_module = sky_vs;
    skp.fragment_module = sky_fs;
    skp.vertex_entry = "vs_main";
    skp.fragment_entry = "fs_main";
    skp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    skp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    skp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    skp.vertex_buffer_count = 1;
    skp.vertex_buffers = &sky_vbl;
    skp.blend_state.write_mask = 0x0F;
    skp.depth_stencil.depth_test_enabled = 1;
    skp.depth_stencil.depth_write_enabled = 0; // skybox never occludes
    skp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS_EQUAL;
    skp.bind_group_layouts[0] = frame_bgl;
    skp.bind_group_layout_count = 1;
    skp.color_target_format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT; // HDR intermediate
    sm.pipeline = dev.create_render_pipeline.?(dev, &skp);
    if (sm.pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "skybox: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }
    sm.vbo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = &sky_verts,
        .size = @sizeOf(@TypeOf(sky_verts)),
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (sm.vbo == c.KE_GPU_INVALID_HANDLE) return false;
    sm.ibo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = &sky_idx,
        .size = @sizeOf(@TypeOf(sky_idx)),
        .usage = c.KE_GPU_BUFFER_USAGE_INDEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (sm.ibo == c.KE_GPU_INVALID_HANDLE) return false;
    return true;
}

// Draws last within the forward render pass — depth LEQUAL, no write, so it
// only fills the background pixels the opaque meshes did not cover.
// frame_bind_group is the same set-0 bind group the forward draws already
// bound (rebuilt on env change by the parent module).
pub fn draw(sm: *const SkyboxModule, rp: [*c]c.ke_gpu_render_pass, frame_bind_group: c.ke_gpu_bind_group) void {
    rp.*.set_pipeline.?(rp, sm.pipeline);
    rp.*.set_bind_group.?(rp, 0, frame_bind_group, null, 0);
    rp.*.set_vertex_buffer.?(rp, 0, sm.vbo, 0);
    rp.*.set_index_buffer.?(rp, sm.ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
    rp.*.draw_indexed.?(rp, sky_idx.len, 1, 0, 0, 0);
}

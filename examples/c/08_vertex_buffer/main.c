#include <kernel_engine/common/error.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_commands.h>
#include <kernel_engine/render/gpu/gpu_enums.h>
#include <kernel_engine/render/gpu/gpu_surface_ext.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>

#include "mesh_vert.h"
#include "mesh_frag.h"

#include <stdio.h>

static void die(const char *msg, ke_error *err)
{
    if (err) { ke_error_fatal(err); }
    ke_error fallback = { .type = &KE_ERROR_GENERAL, .message = msg, .file = __FILE__, .line = __LINE__, .cause = NULL };
    ke_error_fatal(&fallback);
}

typedef struct { float x, y, r, g, b; } vertex_t;

static const vertex_t vertices[] = {
    { -0.5f, -0.5f,  1.0f, 0.0f, 0.0f },
    {  0.5f, -0.5f,  0.0f, 1.0f, 0.0f },
    {  0.5f,  0.5f,  0.0f, 0.0f, 1.0f },
    { -0.5f,  0.5f,  1.0f, 1.0f, 0.0f },
};

static const uint16_t indices[] = { 0, 1, 2, 0, 2, 3 };

int main(void)
{
    printf("--- c_demo_08: indexed quad (vertex buffer) ---\n");

    ke_error *err = NULL;

    // ── Window ───────────────────────────────────────────────────────────────

    ke_window_glfw_params wp = {
        .logger     = NULL,
        .input      = NULL,
        .title      = "c_demo_08 vertex buffer",
        .width      = 800,
        .height     = 600,
        .fullscreen = false,
    };
    ke_window_handle win = ke_window_glfw_create(&wp, &err);
    if (!win.ref) die("window create failed", err);
    if (!win.ref->on_initialize(win.ref, &err)) die("window init failed", err);

    // ── GPU device ────────────────────────────────────────────────────────────

    ke_gpu_device_webgpu_params dp = {
        .logger            = NULL,
        .window            = win.ref,
        .enable_validation = 1,
    };
    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&dp, &err);
    if (!gpu.ref) die("gpu device create failed", err);

    const ke_gpu_surface_ext *surf_ext =
        (const ke_gpu_surface_ext *)gpu.ref->query_extension(gpu.ref, KE_GPU_SURFACE_EXT_NAME);
    if (!surf_ext) die("surface extension not available", NULL);

    // ── Vertex buffer ─────────────────────────────────────────────────────────

    ke_gpu_buffer_params vbp = {
        .initial_data       = vertices,
        .size               = sizeof(vertices),
        .usage              = KE_GPU_BUFFER_USAGE_VERTEX | KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    };
    ke_gpu_buffer vbo = gpu.ref->create_buffer(gpu.ref, &vbp, &err);
    if (vbo == KE_GPU_INVALID_HANDLE) die("vertex buffer creation failed", err);

    // ── Index buffer ──────────────────────────────────────────────────────────

    ke_gpu_buffer_params ibp = {
        .initial_data       = indices,
        .size               = sizeof(indices),
        .usage              = KE_GPU_BUFFER_USAGE_INDEX | KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    };
    ke_gpu_buffer ibo = gpu.ref->create_buffer(gpu.ref, &ibp, &err);
    if (ibo == KE_GPU_INVALID_HANDLE) die("index buffer creation failed", err);

    // ── Shaders ───────────────────────────────────────────────────────────────

    ke_gpu_shader_module_params vsp = {
        .code        = mesh_vert_spv,
        .byte_size   = sizeof(mesh_vert_spv),
        .entry_point = "main",
    };
    ke_gpu_shader_module vs = gpu.ref->create_shader_module(gpu.ref, &vsp, &err);

    ke_gpu_shader_module_params fsp = {
        .code        = mesh_frag_spv,
        .byte_size   = sizeof(mesh_frag_spv),
        .entry_point = "main",
    };
    ke_gpu_shader_module fs = gpu.ref->create_shader_module(gpu.ref, &fsp, &err);

    if (vs == KE_GPU_INVALID_HANDLE) die("vertex shader failed", NULL);
    if (fs == KE_GPU_INVALID_HANDLE) die("fragment shader failed", NULL);

    // ── Pipeline ─────────────────────────────────────────────────────────────
    // layout: location 0 = vec2 pos, location 1 = vec3 color, interleaved

    ke_gpu_vertex_attribute attrs[] = {
        { .shader_location = 0, .format = KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = 0 },
        { .shader_location = 1, .format = KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = sizeof(float) * 2 },
    };
    ke_gpu_vertex_buffer_layout vbl = {
        .stride          = sizeof(vertex_t),
        .step_mode       = KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 2,
        .attributes      = attrs,
    };
    ke_gpu_blend_state blend = {
        .blend_enabled = 0,
        .src_color = KE_GPU_BLEND_FACTOR_ONE,
        .dst_color = KE_GPU_BLEND_FACTOR_ZERO,
        .color_op  = KE_GPU_BLEND_OP_ADD,
        .src_alpha = KE_GPU_BLEND_FACTOR_ONE,
        .dst_alpha = KE_GPU_BLEND_FACTOR_ZERO,
        .alpha_op  = KE_GPU_BLEND_OP_ADD,
        .write_mask = 0x0F,
    };
    ke_gpu_render_pipeline_params pp = {
        .vertex_module           = vs,
        .fragment_module         = fs,
        .primitive_topology      = KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .cull_mode               = KE_GPU_CULL_MODE_NONE,
        .front_face              = KE_GPU_FRONT_FACE_CCW,
        .vertex_buffer_count     = 1,
        .vertex_buffers          = &vbl,
        .blend_state             = blend,
        .depth_stencil           = { .depth_test_enabled = 0 },
        .bind_group_layout_count = 0,
        .alpha_to_coverage_enabled = 0,
    };
    ke_gpu_pipeline pipeline = gpu.ref->create_render_pipeline(gpu.ref, &pp);
    if (pipeline == KE_GPU_INVALID_HANDLE) die("pipeline creation failed", NULL);

    gpu.ref->destroy_shader_module(gpu.ref, vs);
    gpu.ref->destroy_shader_module(gpu.ref, fs);

    ke_gpu_queue q = gpu.ref->get_default_queue(gpu.ref);

    // ── Loop ──────────────────────────────────────────────────────────────────

    printf("Rendering quad. Close the window to exit.\n");

    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref, NULL);

        ke_gpu_texture_view view = surf_ext->acquire_current_texture_view(surf_ext);
        if (view == KE_GPU_INVALID_HANDLE) continue;

        ke_gpu_clear_value clear = { .color = { 0.1f, 0.1f, 0.15f, 1.0f } };
        ke_gpu_color_attachment ca = {
            .view        = view,
            .load_op     = KE_GPU_LOAD_OP_CLEAR,
            .store_op    = KE_GPU_STORE_OP_STORE,
            .clear_value = clear,
        };
        ke_gpu_render_pass_params rpp = {
            .color_attachments      = &ca,
            .color_attachment_count = 1,
            .depth_stencil_attachment = NULL,
        };

        ke_gpu_command_encoder *enc = gpu.ref->create_command_encoder(gpu.ref);
        ke_gpu_render_pass *rp = enc->begin_render_pass(enc, &rpp);
        rp->set_pipeline(rp, pipeline);
        rp->set_vertex_buffer(rp, 0, vbo, 0);
        rp->set_index_buffer(rp, ibo, KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp->draw_indexed(rp, 6, 1, 0, 0, 0);
        rp->end(rp);

        ke_gpu_command_buffer *cmd = enc->finish(enc);
        enc->destroy(enc);

        ke_gpu_command_buffer *cmds[] = { cmd };
        gpu.ref->queue_submit(gpu.ref, q, cmds, 1);
        cmd->destroy(cmd);
        gpu.ref->queue_present(gpu.ref, q);
        gpu.ref->destroy_texture_view(gpu.ref, view);
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    gpu.ref->destroy_pipeline(gpu.ref, pipeline);
    gpu.ref->destroy_buffer(gpu.ref, ibo);
    gpu.ref->destroy_buffer(gpu.ref, vbo);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref, NULL);
    win.destroy(win.ref);

    printf("--- Done ---\n");
    return 0;
}

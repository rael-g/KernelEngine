#include <kernel_engine/common/error.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/gpu_enums.h>
#include <kernel_engine/render/gpu_surface_ext.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>

#include "triangle_vert.h"
#include "triangle_frag.h"

#include <stdio.h>

static void die(const char *msg, ke_error *err)
{
    if (err)
        fprintf(stderr, "ERROR [%s]: %s\n", err->type->name, err->message);
    else
        fprintf(stderr, "ERROR: %s\n", msg);
    __builtin_trap();
}

int main(void)
{
    printf("--- c_demo_06: triangle ---\n");

    ke_error *err = NULL;

    // ── Window ───────────────────────────────────────────────────────────────

    ke_window_glfw_params wp = {
        .logger     = NULL,
        .input      = NULL,
        .title      = "c_demo_06 triangle",
        .width      = 800,
        .height     = 600,
        .fullscreen = false,
    };
    ke_window_handle win = ke_window_glfw_create(&wp, &err);
    if (!win.ref) die("window create failed", err);

    if (!win.ref->on_initialize(win.ref, &err)) die("window init failed", err);

    // ── GPU device (with surface) ─────────────────────────────────────────────

    ke_gpu_device_webgpu_params dp = {
        .logger            = NULL,
        .window            = win.ref,
        .enable_validation = 1,
    };
    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&dp, &err);
    if (!gpu.ref) die("gpu device create failed", err);

    // ── Surface extension ─────────────────────────────────────────────────────

    const ke_gpu_surface_ext *surf_ext =
        (const ke_gpu_surface_ext *)gpu.ref->query_extension(gpu.ref, KE_GPU_SURFACE_EXT_NAME);
    if (!surf_ext) die("surface extension not available", NULL);

    // ── Shaders ───────────────────────────────────────────────────────────────

    ke_gpu_shader_module_params vsp = {
        .code        = triangle_vert_spv,
        .byte_size   = sizeof(triangle_vert_spv),
        .entry_point = "main",
    };
    ke_gpu_shader_module vs = gpu.ref->create_shader_module(gpu.ref, &vsp);

    ke_gpu_shader_module_params fsp = {
        .code        = triangle_frag_spv,
        .byte_size   = sizeof(triangle_frag_spv),
        .entry_point = "main",
    };
    ke_gpu_shader_module fs = gpu.ref->create_shader_module(gpu.ref, &fsp);

    if (vs == KE_GPU_INVALID_HANDLE) die("vertex shader creation failed", NULL);
    if (fs == KE_GPU_INVALID_HANDLE) die("fragment shader creation failed", NULL);

    // ── Pipeline ─────────────────────────────────────────────────────────────

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
        .vertex_module        = vs,
        .fragment_module      = fs,
        .primitive_topology   = KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .cull_mode            = KE_GPU_CULL_MODE_NONE,
        .front_face           = KE_GPU_FRONT_FACE_CCW,
        .vertex_buffer_count  = 0,
        .vertex_buffers       = NULL,
        .blend_state          = blend,
        .depth_stencil        = { .depth_test_enabled = 0 },
        .bind_group_layout_count = 0,
        .alpha_to_coverage_enabled = 0,
    };
    ke_gpu_pipeline pipeline = gpu.ref->create_render_pipeline(gpu.ref, &pp);
    if (pipeline == KE_GPU_INVALID_HANDLE) die("pipeline creation failed", NULL);

    gpu.ref->destroy_shader_module(gpu.ref, vs);
    gpu.ref->destroy_shader_module(gpu.ref, fs);

    ke_gpu_queue q = gpu.ref->get_default_queue(gpu.ref);

    // ── Loop ──────────────────────────────────────────────────────────────────

    printf("Rendering triangle. Close the window to exit.\n");

    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref, NULL);

        ke_gpu_texture_view view = surf_ext->acquire_current_texture_view(surf_ext);
        if (view == KE_GPU_INVALID_HANDLE) continue; // minimised or surface lost

        ke_gpu_clear_value clear = { .color = { 0.1f, 0.1f, 0.1f, 1.0f } };
        ke_gpu_color_attachment ca = {
            .view        = view,
            .load_op     = KE_GPU_LOAD_OP_CLEAR,
            .store_op    = KE_GPU_STORE_OP_STORE,
            .clear_value = clear,
        };
        ke_gpu_render_pass_params rpp = {
            .color_attachments        = &ca,
            .color_attachment_count   = 1,
            .depth_stencil_attachment = NULL,
        };

        void *enc = gpu.ref->encoder_create(gpu.ref);
        void *rp  = gpu.ref->encoder_begin_render_pass(gpu.ref, enc, &rpp);
        gpu.ref->rp_set_pipeline(gpu.ref, rp, pipeline);
        gpu.ref->rp_draw(gpu.ref, rp, 3, 1, 0, 0);
        gpu.ref->rp_end(gpu.ref, rp);

        ke_gpu_command_buffer *cmd = gpu.ref->encoder_finish(gpu.ref, enc);
        gpu.ref->encoder_destroy(gpu.ref, enc);

        ke_gpu_command_buffer *cmds[] = { cmd };
        gpu.ref->queue_submit(gpu.ref, q, cmds, 1);
        gpu.ref->cmd_buffer_destroy(gpu.ref, cmd);
        gpu.ref->queue_present(gpu.ref, q);
        gpu.ref->destroy_texture_view(gpu.ref, view);
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    gpu.ref->destroy_pipeline(gpu.ref, pipeline);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref, NULL);
    win.destroy(win.ref);

    printf("--- Done ---\n");
    return 0;
}

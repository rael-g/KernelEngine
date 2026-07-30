#include <kernel_engine/common/error.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_commands.h>
#include <kernel_engine/render/gpu/gpu_enums.h>
#include <kernel_engine/render/gpu/gpu_surface_ext.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>

#include "rotate_vert.h"
#include "rotate_frag.h"

#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static void die(const char *msg, ke_error *err)
{
    if (err) { ke_error_fatal(err); }
    ke_error fallback = { .type = &KE_ERROR_GENERAL, .message = msg, .file = __FILE__, .line = __LINE__, .cause = NULL };
    ke_error_fatal(&fallback);
}

static double elapsed_seconds(void)
{
#if defined(_WIN32)
    return (double)clock() / (double)CLOCKS_PER_SEC;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
#endif
}

int main(void)
{
    printf("--- c_demo_07: rotating triangle (uniform buffer) ---\n");

    ke_error *err = NULL;

    // ── Window ───────────────────────────────────────────────────────────────

    ke_window_glfw_params wp = {
        .logger     = NULL,
        .input      = NULL,
        .title      = "c_demo_07 uniform",
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

    // ── Uniform buffer (float angle, padded to 16 bytes for WebGPU) ──────────

    float uniform_data[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
    ke_gpu_buffer_params ubp = {
        .initial_data    = uniform_data,
        .size            = sizeof(uniform_data),
        .usage           = KE_GPU_BUFFER_USAGE_UNIFORM | KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    };
    ke_gpu_buffer ubo = gpu.ref->create_buffer(gpu.ref, &ubp, &err);
    if (ubo == KE_GPU_INVALID_HANDLE) die("uniform buffer creation failed", err);

    // ── Bind group layout ─────────────────────────────────────────────────────

    ke_gpu_bind_group_layout_entry bgl_entry = {
        .binding           = 0,
        .visibility        = KE_GPU_SHADER_STAGE_VERTEX,
        .type              = KE_GPU_BINDING_TYPE_BUFFER,
        .has_dynamic_offset = 0,
    };
    ke_gpu_bind_group_layout_params bgl_params = {
        .entry_count = 1,
        .entries     = &bgl_entry,
    };
    ke_gpu_bind_group_layout bgl = gpu.ref->create_bind_group_layout(gpu.ref, &bgl_params);
    if (bgl == KE_GPU_INVALID_HANDLE) die("bind group layout creation failed", NULL);

    // ── Bind group ────────────────────────────────────────────────────────────

    ke_gpu_bind_group_entry bg_entry = {
        .binding      = 0,
        .type         = KE_GPU_BINDING_TYPE_BUFFER,
        .buffer       = ubo,
        .buffer_offset = 0,
        .buffer_size  = sizeof(uniform_data),
    };
    ke_gpu_bind_group_params bg_params = {
        .layout      = bgl,
        .entry_count = 1,
        .entries     = &bg_entry,
    };
    ke_gpu_bind_group bg = gpu.ref->create_bind_group(gpu.ref, &bg_params, &err);
    if (bg == KE_GPU_INVALID_HANDLE) die("bind group creation failed", err);

    // ── Shaders ───────────────────────────────────────────────────────────────

    ke_gpu_shader_module_params vsp = {
        .code        = rotate_vert_spv,
        .byte_size   = sizeof(rotate_vert_spv),
        .entry_point = "main",
    };
    ke_gpu_shader_module vs = gpu.ref->create_shader_module(gpu.ref, &vsp, &err);

    ke_gpu_shader_module_params fsp = {
        .code        = rotate_frag_spv,
        .byte_size   = sizeof(rotate_frag_spv),
        .entry_point = "main",
    };
    ke_gpu_shader_module fs = gpu.ref->create_shader_module(gpu.ref, &fsp, &err);

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
        .vertex_module           = vs,
        .fragment_module         = fs,
        .primitive_topology      = KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .cull_mode               = KE_GPU_CULL_MODE_NONE,
        .front_face              = KE_GPU_FRONT_FACE_CCW,
        .vertex_buffer_count     = 0,
        .vertex_buffers          = NULL,
        .blend_state             = blend,
        .depth_stencil           = { .depth_test_enabled = 0 },
        .bind_group_layouts[0]   = bgl,
        .bind_group_layout_count = 1,
        .alpha_to_coverage_enabled = 0,
    };
    ke_gpu_pipeline pipeline = gpu.ref->create_render_pipeline(gpu.ref, &pp);
    if (pipeline == KE_GPU_INVALID_HANDLE) die("pipeline creation failed", NULL);

    gpu.ref->destroy_shader_module(gpu.ref, vs);
    gpu.ref->destroy_shader_module(gpu.ref, fs);

    ke_gpu_queue q = gpu.ref->get_default_queue(gpu.ref);

    // ── Loop ──────────────────────────────────────────────────────────────────

    printf("Rendering rotating triangle. Close the window to exit.\n");

    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref, NULL);

        // Update uniform (angle in radians, one revolution per second)
        float angle = (float)(fmod(elapsed_seconds(), 1.0) * 6.2831853);
        uniform_data[0] = angle;
        gpu.ref->write_buffer(gpu.ref, ubo, 0, uniform_data, sizeof(uniform_data));

        ke_gpu_texture_view view = surf_ext->acquire_current_texture_view(surf_ext);
        if (view == KE_GPU_INVALID_HANDLE) continue;

        ke_gpu_clear_value clear = { .color = { 0.1f, 0.1f, 0.1f, 1.0f } };
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
        rp->set_bind_group(rp, 0, bg, NULL, 0);
        rp->draw(rp, 3, 1, 0, 0);
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
    gpu.ref->destroy_bind_group(gpu.ref, bg);
    gpu.ref->destroy_bind_group_layout(gpu.ref, bgl);
    gpu.ref->destroy_buffer(gpu.ref, ubo);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref, NULL);
    win.destroy(win.ref);

    printf("--- Done ---\n");
    return 0;
}

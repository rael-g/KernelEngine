#include <kernel_engine/result/result.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_commands.h>
#include <kernel_engine/render/gpu/gpu_enums.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>

static const char rotate_vs_wgsl[] = {
#embed "rotate_vs.wgsl"
    , 0};
static const char rotate_fs_wgsl[] = {
#embed "rotate_fs.wgsl"
    , 0};

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void die_result(const char *what, ke_result result)
{
    fprintf(stderr, "%s failed with result code 0x%08x\n", what, (unsigned)result);
    exit(1);
}

static void check(const char *what, ke_result result)
{
    if (result != KE_OK) die_result(what, result);
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

    ke_window_glfw_params wp = {
        .input      = NULL,
        .title      = "c_demo_07 uniform",
        .width      = 800,
        .height     = 600,
        .fullscreen = false,
    };
    ke_window_handle win = { 0 };
    ke_result made_window = ke_window_glfw_create(&wp, &win);
    if (made_window != KE_OK) die_result("window create failed", made_window);
    ke_result window_ready = win.ref->on_initialize(win.ref);
    if (window_ready != KE_OK) die_result("window init failed", window_ready);

    ke_gpu_device_webgpu_params dp = {
        .enable_validation = 1,
    };
    ke_gpu_device_handle gpu = { 0 };
    check("gpu device create", ke_gpu_device_webgpu_create(&dp, &gpu));

    ke_gpu_render_target_handle target = { 0 };
    check("render target create", ke_gpu_render_target_webgpu_window_create(&(ke_gpu_render_target_webgpu_window_params){ .device = gpu.ref, .window = win.ref }, &target));

    float uniform_data[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
    ke_gpu_buffer_params ubp = {
        .initial_data    = uniform_data,
        .size            = sizeof(uniform_data),
        .usage           = KE_GPU_BUFFER_USAGE_UNIFORM | KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    };
    ke_gpu_buffer ubo = { 0 };
    check("uniform buffer creation", gpu.ref->create_buffer(gpu.ref, &ubp, &ubo));

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
    ke_gpu_bind_group_layout bgl = { 0 };
    check("bind group layout creation", gpu.ref->create_bind_group_layout(gpu.ref, &bgl_params, &bgl));

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
    ke_gpu_bind_group bg = { 0 };
    check("bind group creation", gpu.ref->create_bind_group(gpu.ref, &bg_params, &bg));

    ke_gpu_shader_module_params vsp = {
        .code        = rotate_vs_wgsl,
        .byte_size   = strlen(rotate_vs_wgsl),
        .label = "vs_main",
    };
    ke_gpu_shader_module vs = { 0 };
    check("create_shader_module", gpu.ref->create_shader_module(gpu.ref, &vsp, &vs));

    ke_gpu_shader_module_params fsp = {
        .code        = rotate_fs_wgsl,
        .byte_size   = strlen(rotate_fs_wgsl),
        .label = "fs_main",
    };
    ke_gpu_shader_module fs = { 0 };
    check("create_shader_module", gpu.ref->create_shader_module(gpu.ref, &fsp, &fs));


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
        .color_target_formats = { target.ref->format(target.ref) },
        .color_target_count = 1,
        .vertex_module           = vs,
        .fragment_module         = fs,
        .vertex_entry = "vs_main",
        .fragment_entry = "fs_main",
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
    ke_gpu_pipeline pipeline = { 0 };
    check("pipeline creation", gpu.ref->create_render_pipeline(gpu.ref, &pp, &pipeline));

    gpu.ref->destroy_shader_module(gpu.ref, vs);
    gpu.ref->destroy_shader_module(gpu.ref, fs);

    ke_gpu_queue q = gpu.ref->get_default_queue(gpu.ref);

    printf("Rendering rotating triangle. Close the window to exit.\n");

    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref);

        float angle = (float)(fmod(elapsed_seconds(), 1.0) * 6.2831853);
        uniform_data[0] = angle;
        gpu.ref->write_buffer(gpu.ref, ubo, 0, uniform_data, sizeof(uniform_data));

        ke_gpu_texture_view view = { 0 };
        check("acquire", target.ref->acquire(target.ref, &view));
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

        ke_gpu_command_encoder_handle enc_handle = { 0 };
        check("create_command_encoder", gpu.ref->create_command_encoder(gpu.ref, NULL, &enc_handle));

        ke_gpu_command_encoder *enc = enc_handle.ref;
        ke_gpu_render_pass *rp = enc->begin_render_pass(enc, &rpp);
        rp->set_pipeline(rp, pipeline);
        rp->set_bind_group(rp, 0, bg, NULL, 0);
        rp->draw(rp, 3, 1, 0, 0);
        rp->end(rp);

        ke_gpu_command_buffer_handle cmd = { 0 };
        check("finish", enc->finish(enc, &cmd));
        enc_handle.destroy(enc);

        ke_gpu_command_buffer *cmds[] = { cmd.ref };
        gpu.ref->queue_submit(gpu.ref, q, cmds, 1);
        cmd.destroy(cmd.ref);
        check("present", target.ref->present(target.ref));
        gpu.ref->queue_poll(gpu.ref, q);
    }

    gpu.ref->destroy_pipeline(gpu.ref, pipeline);
    gpu.ref->destroy_bind_group(gpu.ref, bg);
    gpu.ref->destroy_bind_group_layout(gpu.ref, bgl);
    gpu.ref->destroy_buffer(gpu.ref, ubo);
    target.destroy(target.ref);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref);
    win.destroy(win.ref);

    printf("--- Done ---\n");
    return 0;
}

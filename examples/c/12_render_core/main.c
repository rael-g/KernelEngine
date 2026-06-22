#include <kernel_engine/common/error.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/gpu_enums.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/core/render_core.h>
#include <kernel_engine/render/core/render_core_create.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>

#include "triangle_vert.h"
#include "triangle_frag.h"

#include <stdio.h>

static void die(const char *msg, ke_error *err)
{
    if (err) fprintf(stderr, "ERROR [%s]: %s\n", err->type->name, err->message);
    else     fprintf(stderr, "ERROR: %s\n", msg);
    __builtin_trap();
}

int main(void)
{
    printf("--- c_demo_12: triangle through the render core (L5) ---\n");
    ke_error *err = NULL;

    ke_window_glfw_params wp = {
        .logger = NULL, .input = NULL,
        .title = "c_demo_12 render core", .width = 800, .height = 600,
    };
    ke_window_handle win = ke_window_glfw_create(&wp, &err);
    if (!win.ref) die("window", err);
    if (!win.ref->on_initialize(win.ref, &err)) die("window init", err);

    ke_gpu_device_webgpu_params dp = { .logger = NULL, .window = win.ref, .enable_validation = 1 };
    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&dp, &err);
    if (!gpu.ref) die("gpu device", err);

    ke_ecs_flecs_params ep = { .reserved = 0 };
    ke_ecs_handle ecs = ke_ecs_flecs_create(&ep, &err);
    if (!ecs.ref) die("ecs", err);

    ke_render_core_handle core = ke_render_core_create(gpu.ref, ecs.ref, &err);
    if (!core.ref) die("render core", err);

    // ── Triangle pipeline — engine-level setup via the device ────────────────
    ke_gpu_shader_module vs = gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = triangle_vert_spv, .byte_size = sizeof(triangle_vert_spv), .entry_point = "main" });
    ke_gpu_shader_module fs = gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = triangle_frag_spv, .byte_size = sizeof(triangle_frag_spv), .entry_point = "main" });
    if (vs == KE_GPU_INVALID_HANDLE || fs == KE_GPU_INVALID_HANDLE) die("shaders", NULL);

    ke_gpu_render_pipeline_params pp = {
        .vertex_module = vs, .fragment_module = fs,
        .primitive_topology = KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .cull_mode = KE_GPU_CULL_MODE_NONE, .front_face = KE_GPU_FRONT_FACE_CCW,
        .blend_state = { .blend_enabled = 0, .src_color = KE_GPU_BLEND_FACTOR_ONE,
                         .dst_color = KE_GPU_BLEND_FACTOR_ZERO, .color_op = KE_GPU_BLEND_OP_ADD,
                         .src_alpha = KE_GPU_BLEND_FACTOR_ONE, .dst_alpha = KE_GPU_BLEND_FACTOR_ZERO,
                         .alpha_op = KE_GPU_BLEND_OP_ADD, .write_mask = 0x0F },
        .depth_stencil = { .depth_test_enabled = 0 },
        .color_target_format = 0, // swapchain surface format
    };
    ke_gpu_pipeline pipeline = gpu.ref->create_render_pipeline(gpu.ref, &pp);
    if (pipeline == KE_GPU_INVALID_HANDLE) die("pipeline", NULL);
    gpu.ref->destroy_shader_module(gpu.ref, vs);
    gpu.ref->destroy_shader_module(gpu.ref, fs);

    // ── Pass I/O: this pass writes the backbuffer ────────────────────────────
    const char *writes[] = { "backbuffer" };
    ke_render_pass_io io = { .reads = NULL, .reads_count = 0, .writes = writes, .writes_count = 1 };

    printf("Triangle drawn through ke_render_core. Close the window to exit.\n");
    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref, NULL);

        if (!core.ref->begin_frame(core.ref, &err)) continue; // backbuffer not ready

        ke_render_pass_ctx *pc = core.ref->begin_pass(core.ref, NULL, &io);
        ke_gpu_render_pass *rp = pc->begin_render(pc);
        rp->set_pipeline(rp, pipeline);
        rp->draw(rp, 3, 1, 0, 0);
        rp->end(rp);
        core.ref->end_pass(core.ref, pc);

        core.ref->end_frame(core.ref, &err);
    }

    gpu.ref->destroy_pipeline(gpu.ref, pipeline);
    core.destroy(core.ref);
    ecs.destroy(ecs.ref);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref, NULL);
    win.destroy(win.ref);
    printf("--- Done ---\n");
    return 0;
}

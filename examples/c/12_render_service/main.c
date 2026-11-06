#include <kernel_engine/result/result.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_enums.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/service/pass_context.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/render/binder_grouped/resource_binder_grouped_create.h>
#include <kernel_engine/render/gpu/gpu_commands.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/task_pool/enki/enki_task_pool.h>
#include <kernel_engine/file_system/std/file_system_std_create.h>
#include <kernel_engine/io/pool/io_pool_create.h>

static const char triangle_wgsl[] = {
#embed "triangle.wgsl"
    , 0};

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void die_result(const char *what, ke_result result)
{
    fprintf(stderr, "%s failed with result code 0x%08x\n", what, (unsigned)result);
    exit(1);
}

static void die(const char *what)
{
    fprintf(stderr, "%s\n", what);
    exit(1);
}

static void check(const char *what, ke_result result)
{
    if (result != KE_OK) die_result(what, result);
}

int main(void)
{
    printf("--- c_demo_12: triangle through the render core (L5) ---\n");
    ke_window_glfw_config wp = {
        .title = "c_demo_12 render core", .width = 800, .height = 600,
    };
    ke_window_handle win = { 0 };
    ke_result made_window = ke_window_glfw_create(NULL, &wp, &win);
    if (made_window != KE_OK) die_result("window", made_window);
    ke_result window_ready = win.ref->on_initialize(win.ref);
    if (window_ready != KE_OK) die_result("window init", window_ready);

    ke_gpu_device_webgpu_config dp = { .enable_validation = 1 };
    ke_gpu_device_handle gpu = { 0 };
    check("gpu device", ke_gpu_device_webgpu_create(NULL, &dp, &gpu));

    ke_gpu_render_target_handle target = { 0 };
    check("render target", ke_gpu_render_target_webgpu_window_create(&(ke_gpu_render_target_webgpu_window_params){ .device = gpu.ref, .window = win.ref }, &target));

    ke_ecs_handle ecs = { 0 };
    ke_result made_ecs = ke_ecs_flecs_create(NULL, &ecs);
    if (made_ecs != KE_OK) die_result("ecs", made_ecs);

    ke_task_pool_handle pool = { 0 };
    check("task pool", ke_task_pool_enki_create(NULL, &pool));
    ke_file_system_handle files = { 0 };
    check("file system", ke_file_system_std_create(NULL, &files));
    ke_io_handle file_io = { 0 };
    check("io", ke_io_pool_create(pool.ref, files.ref, &file_io));

    ke_render_resource_binder_handle binder = { 0 };
    check("resource binder", ke_render_resource_binder_grouped_create(
        &(ke_render_resource_binder_grouped_params){ .device = gpu.ref, .shader_dir = "shaders", .io = file_io.ref }, &binder));

    ke_render_service_handle core = { 0 };
    check("render core", ke_render_service_create(&(ke_render_service_params){
        .device = gpu.ref, .target = target.ref, .ecs = ecs.ref, .shader_dir = "shaders", .io = file_io.ref, .binder = binder.ref }, &core));

    if (gpu.ref->shader_language(gpu.ref) != KE_GPU_SHADER_LANG_WGSL) die("expected WGSL backend");

    ke_gpu_shader_module shader = { 0 };
    check("shader", gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = triangle_wgsl, .byte_size = strlen(triangle_wgsl), .label = "triangle" }, &shader));

    ke_gpu_render_pipeline_params pp = {
        .vertex_module = shader, .fragment_module = shader,
        .vertex_entry = "vs_main", .fragment_entry = "fs_main",
        .primitive_topology = KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .cull_mode = KE_GPU_CULL_MODE_NONE, .front_face = KE_GPU_FRONT_FACE_CCW,
        .blend_state = { .blend_enabled = 0, .src_color = KE_GPU_BLEND_FACTOR_ONE,
                         .dst_color = KE_GPU_BLEND_FACTOR_ZERO, .color_op = KE_GPU_BLEND_OP_ADD,
                         .src_alpha = KE_GPU_BLEND_FACTOR_ONE, .dst_alpha = KE_GPU_BLEND_FACTOR_ZERO,
                         .alpha_op = KE_GPU_BLEND_OP_ADD, .write_mask = 0x0F },
        .depth_stencil = { .depth_test_enabled = 0 },
        .color_target_formats = { core.ref->chain_format(core.ref, KE_RENDER_STAGE_OPAQUE) },
        .color_target_count = 1,
    };
    ke_gpu_pipeline pipeline = { 0 };
    check("pipeline", gpu.ref->create_render_pipeline(gpu.ref, &pp, &pipeline));
    gpu.ref->destroy_shader_module(gpu.ref, shader);

    ke_render_chain_link link = { 0 };
    check("join chain", core.ref->join_chain(core.ref, KE_RENDER_STAGE_OPAQUE, KE_RENDER_CHAIN_DRAW_OVER, &link));
    ke_render_pass_io io = { .name = "triangle", .chain = link };

    printf("Triangle drawn through ke_render_service. Close the window to exit.\n");
    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref);

        check("begin_frame", core.ref->begin_frame(core.ref));

        ke_render_pass_ctx *pc = core.ref->begin_pass(core.ref, &io);
        if (pc)
        {
            ke_gpu_render_pass *rp = pc->begin_render(pc);
            rp->set_pipeline(rp, pipeline);
            rp->draw(rp, 3, 1, 0, 0);
            rp->end(rp);
            core.ref->end_pass(core.ref, pc);
        }

        check("end_frame", core.ref->end_frame(core.ref));
    }

    gpu.ref->destroy_pipeline(gpu.ref, pipeline);
    core.ref->leave_chain(core.ref, link);
    core.destroy(core.ref);
    binder.destroy(binder.ref);
    file_io.destroy(file_io.ref);
    files.destroy(files.ref);
    pool.destroy(pool.ref);
    ecs.destroy(ecs.ref);
    target.destroy(target.ref);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref);
    win.destroy(win.ref);
    printf("--- Done ---\n");
    return 0;
}

#include <kernel_engine/result/result.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
#include <kernel_engine/render/binder_grouped/resource_binder_grouped_create.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/view/space/view_space_rh_create.h>
#include <kernel_engine/render/camera/camera_create.h>
#include <kernel_engine/render/scene/scene_resolve_create.h>
#include <kernel_engine/render/frame/frame_create.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/task_pool/task_pool.h>
#include <kernel_engine/task_pool/enki/enki_task_pool.h>
#include <kernel_engine/file_system/std/file_system_std_create.h>
#include <kernel_engine/io/pool/io_pool_create.h>
#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/runtime/runtime_create.h>

#include <stdio.h>
#include <stdlib.h>
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

static double now_seconds(void)
{
#if defined(_WIN32)
    return (double)clock() / (double)CLOCKS_PER_SEC;
#else
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
#endif
}

int main(void)
{
    printf("--- c_demo_13: clear screen via runtime-driven render passes ---\n");
    ke_window_glfw_config wp = {
        .title = "c_demo_13 runtime clear", .width = 1024, .height = 640,
    };
    ke_window_handle win = { 0 };
    ke_result made_window = ke_window_glfw_create(NULL, &wp, &win);
    if (made_window != KE_OK) die_result("window", made_window);
    ke_result window_ready = win.ref->on_initialize(win.ref);
    if (window_ready != KE_OK) die_result("window init", window_ready);

    ke_gpu_device_webgpu_params dp = { .enable_validation = 1 };
    ke_gpu_device_handle gpu = { 0 };
    check("gpu device", ke_gpu_device_webgpu_create(&dp, &gpu));

    ke_gpu_render_target_handle target = { 0 };
    check("render target", ke_gpu_render_target_webgpu_window_create(&(ke_gpu_render_target_webgpu_window_params){ .device = gpu.ref, .window = win.ref }, &target));

    ke_ecs_handle ecs = { 0 };
    ke_result made_ecs = ke_ecs_flecs_create(NULL, &ecs);
    if (made_ecs != KE_OK) die_result("ecs", made_ecs);

    ke_task_pool_handle pool = { 0 };
    ke_result made = ke_task_pool_enki_create(NULL, &pool);
    if (made != KE_OK) die_result("task pool", made);

    ke_runtime_params rp = { 0 };
    ke_runtime_handle rt = { 0 };
    ke_result made_runtime = ke_runtime_create(ecs.ref, pool.ref, &rp, &rt);
    if (made_runtime != KE_OK) die_result("runtime", made_runtime);

    ke_file_system_handle files = { 0 };
    check("file system", ke_file_system_std_create(NULL, &files));
    ke_io_handle file_io = { 0 };
    check("io", ke_io_pool_create(pool.ref, files.ref, &file_io));
    ke_render_resource_binder_handle binder = { 0 };
    check("resource binder", ke_render_resource_binder_grouped_create(&(ke_render_resource_binder_grouped_params){ .device = gpu.ref, .shader_dir = "shaders", .io = file_io.ref }, &binder));
    ke_render_service_handle service = { 0 };
    check("render service", ke_render_service_create(&(ke_render_service_params){
        .device = gpu.ref, .target = target.ref, .ecs = ecs.ref, .shader_dir = "shaders", .io = file_io.ref, .binder = binder.ref }, &service));

    ke_view_space_handle view_space = { 0 };
    ke_result made_view = ke_view_space_rh_create(&view_space);
    if (made_view != KE_OK) die_result("view space", made_view);
    ke_render_camera_handle camera = { 0 };
    check("camera", ke_render_camera_create(view_space.ref, gpu.ref, &camera));

    ke_render_scene_resolve_handle scene = { 0 };
    check("scene resolve", ke_render_scene_resolve_create(&(ke_render_scene_resolve_params){ .runtime = rt.ref, .ecs = ecs.ref, .service = service.ref }, &scene));
    ke_render_frame_handle frame = { 0 };
    check("frame", ke_render_frame_create(&(ke_render_frame_params){
        .runtime = rt.ref, .ecs = ecs.ref, .service = service.ref, .camera = camera.ref,
        .scene = scene.ref }, &frame));

    printf("Clearing the screen through the runtime each tick. Close to exit.\n");
    double prev = now_seconds();
    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref);
        double t = now_seconds();
        ke_result ticked = rt.ref->tick(rt.ref, (float)(t - prev));
        if (ticked != KE_OK) die_result("tick", ticked);
        prev = t;
    }

    ke_result flushed = rt.ref->flush_render(rt.ref);
    if (flushed != KE_OK) die_result("flush render", flushed);
    frame.destroy(frame.ref);
    scene.destroy(scene.ref);
    camera.destroy(camera.ref);
    service.destroy(service.ref);
    binder.destroy(binder.ref);
    view_space.destroy(view_space.ref);
    rt.destroy(rt.ref);
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

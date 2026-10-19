#include <kernel_engine/common/error.h>
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
#include <kernel_engine/scheduler/scheduler.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>
#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/runtime/runtime_create.h>

#include <stdio.h>
#include <time.h>

static void die(const char *msg, ke_error *err)
{
    if (err) { ke_error_fatal(err); }
    ke_error fallback = { .type = &KE_ERROR_GENERAL, .message = msg, .file = __FILE__, .line = __LINE__, .cause = NULL };
    ke_error_fatal(&fallback);
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
    ke_error *err = NULL;

    ke_window_glfw_params wp = {
        .logger = NULL, .input = NULL,
        .title = "c_demo_13 runtime clear", .width = 1024, .height = 640,
    };
    ke_window_handle win = ke_window_glfw_create(&wp, &err);
    if (!win.ref) die("window", err);
    if (!win.ref->on_initialize(win.ref, &err)) die("window init", err);

    ke_gpu_device_webgpu_params dp = { .logger = NULL, .enable_validation = 1 };
    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&dp, &err);
    if (!gpu.ref) die("gpu device", err);

    ke_gpu_render_target_handle target = ke_gpu_render_target_webgpu_window_create(&(ke_gpu_render_target_webgpu_window_params){ .device = gpu.ref, .window = win.ref }, &err);
    if (!target.ref) die("render target", err);

    ke_ecs_flecs_params ep = { .world_id_base = 0 };
    ke_ecs_handle ecs = ke_ecs_flecs_create(&ep, &err);
    if (!ecs.ref) die("ecs", err);

    ke_scheduler_handle sched = ke_scheduler_enki_create(NULL, &err);
    if (!sched.ref) die("scheduler", err);

    ke_runtime_params rp = { 0 };
    ke_runtime_handle rt = ke_runtime_create(ecs.ref, sched.ref, &rp, &err);
    if (!rt.ref) die("runtime", err);

    ke_render_resource_binder_handle binder = ke_render_resource_binder_grouped_create(&(ke_render_resource_binder_grouped_params){ .device = gpu.ref, .shader_dir = "shaders" }, &err);
    if (!binder.ref) die("resource binder", err);
    ke_render_service_handle service = ke_render_service_create(&(ke_render_service_params){
        .device = gpu.ref, .target = target.ref, .ecs = ecs.ref, .shader_dir = "shaders", .binder = binder.ref }, &err);
    if (!service.ref) die("render service", err);

    ke_ndc_convention ndc = gpu.ref->get_ndc_convention(gpu.ref);
    ke_view_space_handle view_space = ke_view_space_rh_create(&err);
    if (!view_space.ref) die("view space", err);
    ke_render_camera_handle camera = ke_render_camera_create(view_space.ref, &ndc, &err);
    if (!camera.ref) die("camera", err);

    ke_render_scene_resolve_handle scene = ke_render_scene_resolve_create(&(ke_render_scene_resolve_params){ .runtime = rt.ref, .ecs = ecs.ref, .service = service.ref }, &err);
    if (!scene.ref) die("scene resolve", err);
    const ke_render_scene_component_ids *ids = scene.ref->component_ids(scene.ref);
    ke_render_frame_handle frame = ke_render_frame_create(&(ke_render_frame_params){
        .runtime = rt.ref, .ecs = ecs.ref, .service = service.ref, .camera = camera.ref,
        .camera_cid = ids->camera, .world_transform_cid = ids->world_transform,
        .directional_light_cid = ids->directional_light, .ambient_light_cid = ids->ambient_light }, &err);
    if (!frame.ref) die("frame", err);

    printf("Clearing the screen through the runtime each tick. Close to exit.\n");
    double prev = now_seconds();
    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref, NULL);
        double t = now_seconds();
        rt.ref->tick(rt.ref, (float)(t - prev), &err);
        prev = t;
    }

    if (!rt.ref->flush_render(rt.ref, &err)) die("flush render", err);
    frame.destroy(frame.ref);
    scene.destroy(scene.ref);
    camera.destroy(camera.ref);
    service.destroy(service.ref);
    binder.destroy(binder.ref);
    view_space.destroy(view_space.ref);
    rt.destroy(rt.ref);
    sched.destroy(sched.ref);
    ecs.destroy(ecs.ref);
    target.destroy(target.ref);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref, NULL);
    win.destroy(win.ref);

    printf("--- Done ---\n");
    return 0;
}

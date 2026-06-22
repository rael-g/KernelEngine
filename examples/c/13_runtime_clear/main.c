#include <kernel_engine/common/error.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/core/render_module_create.h>
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
    if (err) fprintf(stderr, "ERROR [%s]: %s\n", err->type->name, err->message);
    else     fprintf(stderr, "ERROR: %s\n", msg);
    __builtin_trap();
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

    // ── Window + GPU device ──────────────────────────────────────────────────
    ke_window_glfw_params wp = {
        .logger = NULL, .input = NULL,
        .title = "c_demo_13 runtime clear", .width = 1024, .height = 640,
    };
    ke_window_handle win = ke_window_glfw_create(&wp, &err);
    if (!win.ref) die("window", err);
    if (!win.ref->on_initialize(win.ref, &err)) die("window init", err);

    ke_gpu_device_webgpu_params dp = { .logger = NULL, .window = win.ref, .enable_validation = 1 };
    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&dp, &err);
    if (!gpu.ref) die("gpu device", err);

    // ── Runtime triple: ecs + scheduler + runtime ────────────────────────────
    ke_ecs_flecs_params ep = { .reserved = 0 };
    ke_ecs_handle ecs = ke_ecs_flecs_create(&ep, &err);
    if (!ecs.ref) die("ecs", err);

    ke_scheduler_handle sched = ke_scheduler_enki_create(&err);
    if (!sched.ref) die("scheduler", err);

    ke_runtime_params rp = { 0 };
    ke_runtime_handle rt = ke_runtime_create(ecs.ref, sched.ref, &rp, &err);
    if (!rt.ref) die("runtime", err);

    // ── Install the render module — registers begin/clear/end as RENDER systems ─
    ke_render_module_handle render = ke_render_module_create(rt.ref, ecs.ref, gpu.ref, &err);
    if (!render.ref) die("render module", err);

    printf("Clearing the screen through the runtime each tick. Close to exit.\n");
    double prev = now_seconds();
    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref, NULL);
        double t = now_seconds();
        rt.ref->tick(rt.ref, (float)(t - prev), &err);
        prev = t;
    }

    // ── Cleanup (module before runtime: its systems point at the module state) ─
    render.destroy(render.ref);
    rt.destroy(rt.ref);
    sched.destroy(sched.ref);
    ecs.destroy(ecs.ref);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref, NULL);
    win.destroy(win.ref);

    printf("--- Done ---\n");
    return 0;
}

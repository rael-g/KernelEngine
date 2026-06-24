#include <kernel_engine/common/error.h>
#include <kernel_engine/common/math.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/core/render_core.h>
#include <kernel_engine/render/core/render_module_create.h>
#include <kernel_engine/render/components.h>
#include <kernel_engine/spatial/transform.h>
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

// Interleaved position(3) + normal(3) + uv(2) + tangent(3), unit cube centred
// at the origin. The tangent (+U direction per face) and uv matter for the
// vertex stride the forward pipeline expects (11 floats); this example uses the
// white material, so the values are not otherwise visible.
typedef struct { float px, py, pz, nx, ny, nz, u, v, tx, ty, tz; } vtx;
static const vtx cube[] = {
    {-0.5f,-0.5f, 0.5f, 0,0, 1, 0,1, 1,0,0},{ 0.5f,-0.5f, 0.5f, 0,0, 1, 1,1, 1,0,0},{ 0.5f, 0.5f, 0.5f, 0,0, 1, 1,0, 1,0,0},{-0.5f, 0.5f, 0.5f, 0,0, 1, 0,0, 1,0,0}, // +Z
    { 0.5f,-0.5f,-0.5f, 0,0,-1, 0,1,-1,0,0},{-0.5f,-0.5f,-0.5f, 0,0,-1, 1,1,-1,0,0},{-0.5f, 0.5f,-0.5f, 0,0,-1, 1,0,-1,0,0},{ 0.5f, 0.5f,-0.5f, 0,0,-1, 0,0,-1,0,0}, // -Z
    { 0.5f,-0.5f, 0.5f, 1,0, 0, 0,1, 0,0,-1},{ 0.5f,-0.5f,-0.5f, 1,0, 0, 1,1, 0,0,-1},{ 0.5f, 0.5f,-0.5f, 1,0, 0, 1,0, 0,0,-1},{ 0.5f, 0.5f, 0.5f, 1,0, 0, 0,0, 0,0,-1}, // +X
    {-0.5f,-0.5f,-0.5f,-1,0, 0, 0,1, 0,0,1},{-0.5f,-0.5f, 0.5f,-1,0, 0, 1,1, 0,0,1},{-0.5f, 0.5f, 0.5f,-1,0, 0, 1,0, 0,0,1},{-0.5f, 0.5f,-0.5f,-1,0, 0, 0,0, 0,0,1}, // -X
    {-0.5f, 0.5f, 0.5f, 0,1, 0, 0,1, 1,0,0},{ 0.5f, 0.5f, 0.5f, 0,1, 0, 1,1, 1,0,0},{ 0.5f, 0.5f,-0.5f, 0,1, 0, 1,0, 1,0,0},{-0.5f, 0.5f,-0.5f, 0,1, 0, 0,0, 1,0,0}, // +Y
    {-0.5f,-0.5f,-0.5f, 0,-1,0, 0,1, 1,0,0},{ 0.5f,-0.5f,-0.5f, 0,-1,0, 1,1, 1,0,0},{ 0.5f,-0.5f, 0.5f, 0,-1,0, 1,0, 1,0,0},{-0.5f,-0.5f, 0.5f, 0,-1,0, 0,0, 1,0,0}, // -Y
};
static const uint16_t cube_idx[] = {
     0, 1, 2,  0, 2, 3,   4, 5, 6,  4, 6, 7,   8, 9,10,  8,10,11,
    12,13,14, 12,14,15,  16,17,18, 16,18,19,  20,21,22, 20,22,23,
};

int main(void)
{
    printf("--- c_demo_14: forward lit cube through the render core ---\n");
    ke_error *err = NULL;

    ke_window_glfw_params wp = {
        .logger = NULL, .input = NULL,
        .title = "c_demo_14 forward mesh", .width = 800, .height = 600,
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

    ke_scheduler_handle sched = ke_scheduler_enki_create(&err);
    if (!sched.ref) die("scheduler", err);

    ke_runtime_params rtp = { 0 };
    ke_runtime_handle rt = ke_runtime_create(ecs.ref, sched.ref, &rtp, &err);
    if (!rt.ref) die("runtime", err);

    ke_render_module_handle render = ke_render_module_create(rt.ref, ecs.ref, gpu.ref, 1, &err);
    if (!render.ref) die("render module", err);
    ke_render_core *core = ke_render_module_core(render.ref);

    // ── Upload the cube + populate the scene (camera + one mesh entity) ──────
    ke_mesh_handle cube_h = core->upload_mesh(core, cube, sizeof(cube), cube_idx,
                                              sizeof(cube_idx) / sizeof(cube_idx[0]), &err);
    if (!ke_mesh_is_valid(cube_h)) die("upload_mesh", err);

    const float orange[4] = { 0.85f, 0.35f, 0.2f, 1.0f };
    ke_material_handle mat = core->create_material(core, orange, 0.0f, 0.5f, KE_TEXTURE_NONE, KE_TEXTURE_NONE, &err);
    if (!ke_material_is_valid(mat)) die("create_material", err);

    ke_component_id transform_cid = ecs.ref->component_register(ecs.ref, KE_COMPONENT_NAME_TRANSFORM, sizeof(ke_transform_component));
    ke_component_id camera_cid    = ecs.ref->component_register(ecs.ref, KE_COMPONENT_NAME_CAMERA,    sizeof(ke_camera_component));
    ke_component_id mesh_cid      = ecs.ref->component_register(ecs.ref, KE_COMPONENT_NAME_MESH,      sizeof(ke_mesh_component));

    const ke_mat4 identity = { .m = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 } };

    ke_entity cam = ecs.ref->entity_create(ecs.ref);
    ke_transform_component *cam_t = ecs.ref->component_add(ecs.ref, cam, transform_cid);
    *cam_t = (ke_transform_component){ .position = { 1.5f, 1.5f, -3.0f }, .world_matrix = identity };
    ke_camera_component *cam_c = ecs.ref->component_add(ecs.ref, cam, camera_cid);
    *cam_c = (ke_camera_component){ .fov = 60.0f, .near_plane = 0.1f, .far_plane = 100.0f };

    ke_entity ent = ecs.ref->entity_create(ecs.ref);
    ke_transform_component *ent_t = ecs.ref->component_add(ecs.ref, ent, transform_cid);
    *ent_t = (ke_transform_component){ .world_matrix = identity };
    ke_mesh_component *ent_m = ecs.ref->component_add(ecs.ref, ent, mesh_cid);
    *ent_m = (ke_mesh_component){ .mesh = cube_h, .material = mat };

    printf("Drawing a lit cube. Close the window to exit.\n");
    double prev = now_seconds();
    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref, NULL);
        double t = now_seconds();
        rt.ref->tick(rt.ref, (float)(t - prev), &err);
        prev = t;
    }

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

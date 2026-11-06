#include <kernel_engine/result/result.h>
#include <kernel_engine/math/math.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/binder_grouped/resource_binder_grouped_create.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/view/space/view_space_rh_create.h>
#include <kernel_engine/render/camera/camera_create.h>
#include <kernel_engine/render/scene/scene_resolve_create.h>
#include <kernel_engine/render/frame/frame_create.h>
#include <kernel_engine/render/shadow/shadow_create.h>
#include <kernel_engine/render/cluster/cluster_create.h>
#include <kernel_engine/render/gbuffer/gbuffer_create.h>
#include <kernel_engine/render/deferred_lighting/deferred_lighting_create.h>
#include <kernel_engine/render/tonemap/tonemap_create.h>
#include <kernel_engine/render/components.h>
#include <kernel_engine/render/component_fields.h>
#include <kernel_engine/spatial/transform.h>
#include <kernel_engine/spatial/component_fields.h>
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

static ke_entity spawn_entity(ke_ecs *ecs)
{
    ke_entity entity = KE_ENTITY_INVALID;
    check("entity_create", ecs->entity_create(ecs, &entity));
    return entity;
}

static void *attach(ke_ecs *ecs, ke_entity entity, ke_component_id cid)
{
    void *data = NULL;
    check("component_add", ecs->component_add(ecs, entity, cid, &data));
    return data;
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

typedef struct { float px, py, pz, nx, ny, nz, u, v, tx, ty, tz; } vtx;
static const vtx cube[] = {
    {-0.5f,-0.5f, 0.5f, 0,0, 1, 0,1, 1,0,0},{ 0.5f,-0.5f, 0.5f, 0,0, 1, 1,1, 1,0,0},{ 0.5f, 0.5f, 0.5f, 0,0, 1, 1,0, 1,0,0},{-0.5f, 0.5f, 0.5f, 0,0, 1, 0,0, 1,0,0},
    { 0.5f,-0.5f,-0.5f, 0,0,-1, 0,1,-1,0,0},{-0.5f,-0.5f,-0.5f, 0,0,-1, 1,1,-1,0,0},{-0.5f, 0.5f,-0.5f, 0,0,-1, 1,0,-1,0,0},{ 0.5f, 0.5f,-0.5f, 0,0,-1, 0,0,-1,0,0},
    { 0.5f,-0.5f, 0.5f, 1,0, 0, 0,1, 0,0,-1},{ 0.5f,-0.5f,-0.5f, 1,0, 0, 1,1, 0,0,-1},{ 0.5f, 0.5f,-0.5f, 1,0, 0, 1,0, 0,0,-1},{ 0.5f, 0.5f, 0.5f, 1,0, 0, 0,0, 0,0,-1},
    {-0.5f,-0.5f,-0.5f,-1,0, 0, 0,1, 0,0,1},{-0.5f,-0.5f, 0.5f,-1,0, 0, 1,1, 0,0,1},{-0.5f, 0.5f, 0.5f,-1,0, 0, 1,0, 0,0,1},{-0.5f, 0.5f,-0.5f,-1,0, 0, 0,0, 0,0,1},
    {-0.5f, 0.5f, 0.5f, 0,1, 0, 0,1, 1,0,0},{ 0.5f, 0.5f, 0.5f, 0,1, 0, 1,1, 1,0,0},{ 0.5f, 0.5f,-0.5f, 0,1, 0, 1,0, 1,0,0},{-0.5f, 0.5f,-0.5f, 0,1, 0, 0,0, 1,0,0},
    {-0.5f,-0.5f,-0.5f, 0,-1,0, 0,1, 1,0,0},{ 0.5f,-0.5f,-0.5f, 0,-1,0, 1,1, 1,0,0},{ 0.5f,-0.5f, 0.5f, 0,-1,0, 1,0, 1,0,0},{-0.5f,-0.5f, 0.5f, 0,-1,0, 0,0, 1,0,0},
};
static const uint16_t cube_idx[] = {
     0, 1, 2,  0, 2, 3,   4, 5, 6,  4, 6, 7,   8, 9,10,  8,10,11,
    12,13,14, 12,14,15,  16,17,18, 16,18,19,  20,21,22, 20,22,23,
};

typedef struct renderer
{
    ke_render_resource_binder_handle binder;
    ke_render_service_handle service;
    ke_view_space_handle view_space;
    ke_render_camera_handle camera;
    ke_render_scene_resolve_handle scene;
    ke_render_frame_handle frame;
    ke_render_shadow_handle shadow;
    ke_render_cluster_handle cluster;
    ke_render_gbuffer_handle gbuffer;
    ke_render_deferred_lighting_handle deferred;
    ke_render_tonemap_handle tonemap;
} renderer;

static void renderer_compose(renderer *r, ke_runtime *rt, ke_ecs *ecs, ke_gpu_device *gpu, ke_gpu_render_target *target, ke_io *io)
{
    check("resource binder", ke_render_resource_binder_grouped_create(&(ke_render_resource_binder_grouped_params){ .device = gpu, .shader_dir = "shaders", .io = io }, &r->binder));
    check("render service", ke_render_service_create(&(ke_render_service_params){
        .device = gpu, .target = target, .ecs = ecs, .shader_dir = "shaders", .io = io, .binder = r->binder.ref }, &r->service));
    ke_render_service *core = r->service.ref;

    ke_result made_view = ke_view_space_rh_create(&r->view_space);
    if (made_view != KE_OK) die_result("view space", made_view);
    check("camera", ke_render_camera_create(r->view_space.ref, gpu, &r->camera));

    check("scene resolve", ke_render_scene_resolve_create(&(ke_render_scene_resolve_params){ .runtime = rt, .ecs = ecs, .service = core }, &r->scene));

    check("frame", ke_render_frame_create(&(ke_render_frame_params){
        .runtime = rt, .ecs = ecs, .service = core, .camera = r->camera.ref,
        .scene = r->scene.ref }, &r->frame));

    check("shadow pass", ke_render_shadow_create(&(ke_render_shadow_params){
        .scene = r->scene.ref, .frame = r->frame.ref, .runtime = rt, .service = core, .device = gpu, .view_space = r->view_space.ref, .output = "shadow" }, &r->shadow));
    check("cluster pass", ke_render_cluster_create(&(ke_render_cluster_params){
        .scene = r->scene.ref, .frame = r->frame.ref, .runtime = rt, .service = core, .device = gpu, .view_space = r->view_space.ref, .camera = r->camera.ref,
        .output = "clusters" }, &r->cluster));
    check("gbuffer pass", ke_render_gbuffer_create(&(ke_render_gbuffer_params){
        .scene = r->scene.ref, .frame = r->frame.ref, .runtime = rt, .service = core, .device = gpu, .output = "gbuffer" }, &r->gbuffer));
    check("deferred lighting pass", ke_render_deferred_lighting_create(&(ke_render_deferred_lighting_params){
        .scene = r->scene.ref, .frame = r->frame.ref, .runtime = rt, .service = core, .device = gpu, .ibl_enabled = true,
        .gbuffer = "gbuffer", .shadow = "shadow", .clusters = "clusters" }, &r->deferred));
    check("tonemap pass", ke_render_tonemap_create(&(ke_render_tonemap_params){
        .runtime = rt, .service = core, .device = gpu, .frame = r->frame.ref }, &r->tonemap));
}

static void renderer_destroy(renderer *r)
{
    r->tonemap.destroy(r->tonemap.ref);
    r->deferred.destroy(r->deferred.ref);
    r->gbuffer.destroy(r->gbuffer.ref);
    r->cluster.destroy(r->cluster.ref);
    r->shadow.destroy(r->shadow.ref);
    r->frame.destroy(r->frame.ref);
    r->scene.destroy(r->scene.ref);
    r->camera.destroy(r->camera.ref);
    r->service.destroy(r->service.ref);
    r->binder.destroy(r->binder.ref);
    r->view_space.destroy(r->view_space.ref);
}

int main(void)
{
    printf("--- c_demo_14: forward lit cube through the render core ---\n");
    ke_window_glfw_config wp = {
        .title = "c_demo_14 forward mesh", .width = 800, .height = 600,
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
    check("render target", ke_gpu_render_target_webgpu_window_create(gpu.ref, win.ref, NULL, &target));

    ke_ecs_handle ecs = { 0 };
    ke_result made_ecs = ke_ecs_flecs_create(NULL, &ecs);
    if (made_ecs != KE_OK) die_result("ecs", made_ecs);

    ke_task_pool_handle pool = { 0 };
    ke_result made = ke_task_pool_enki_create(NULL, &pool);
    if (made != KE_OK) die_result("task pool", made);

    ke_runtime_params rtp = { 0 };
    ke_runtime_handle rt = { 0 };
    ke_result made_runtime = ke_runtime_create(ecs.ref, pool.ref, &rtp, &rt);
    if (made_runtime != KE_OK) die_result("runtime", made_runtime);

    renderer render;
    ke_file_system_handle files = { 0 };
    check("file system", ke_file_system_std_create(NULL, &files));
    ke_io_handle file_io = { 0 };
    check("io", ke_io_pool_create(pool.ref, files.ref, &file_io));
    renderer_compose(&render, rt.ref, ecs.ref, gpu.ref, target.ref, file_io.ref);
    ke_render_service *core = render.service.ref;

    ke_mesh_handle cube_h = { 0 };
    check("upload_mesh", core->upload_mesh(core, "example:cube", (const ke_mesh_vertex *)cube, sizeof(cube) / sizeof(cube[0]), cube_idx,
                                              sizeof(cube_idx) / sizeof(cube_idx[0]), &cube_h));

    const ke_vec4 orange = { 0.85f, 0.35f, 0.2f, 1.0f };
    ke_material_handle mat = { 0 };
    check("create_material", core->create_material(core, "example:orange", orange, 0.0f, 0.5f, KE_TEXTURE_NONE, KE_TEXTURE_NONE,
                                                    KE_ALPHA_MODE_OPAQUE, 0.5f, 1.5f, 0.05f, NULL, &mat));

    ke_component_id transform_cid = KE_COMPONENT_INVALID;
    ke_result registered_transform_cid = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_TRANSFORM, .size = sizeof(ke_transform_component), .alignment = _Alignof(ke_transform_component), KE_COMPONENT_FIELDS(ke_transform_component_fields) }, &transform_cid);
    if (registered_transform_cid != KE_OK) die_result("component_register", registered_transform_cid);
    ke_component_id world_cid = KE_COMPONENT_INVALID;
    ke_result registered_world_cid = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_WORLD_TRANSFORM, .size = sizeof(ke_world_transform_component), .alignment = _Alignof(ke_world_transform_component) }, &world_cid);
    if (registered_world_cid != KE_OK) die_result("component_register", registered_world_cid);
    ke_component_id camera_cid = KE_COMPONENT_INVALID;
    ke_result registered_camera_cid = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_CAMERA, .size = sizeof(ke_camera_component), .alignment = _Alignof(ke_camera_component), KE_COMPONENT_FIELDS(ke_camera_component_fields) }, &camera_cid);
    if (registered_camera_cid != KE_OK) die_result("component_register", registered_camera_cid);
    ke_component_id mesh_cid = KE_COMPONENT_INVALID;
    ke_result registered_mesh_cid = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_MESH, .size = sizeof(ke_mesh_component), .alignment = _Alignof(ke_mesh_component), KE_COMPONENT_FIELDS(ke_mesh_component_fields) }, &mesh_cid);
    if (registered_mesh_cid != KE_OK) die_result("component_register", registered_mesh_cid);
    ke_component_id light_cid = KE_COMPONENT_INVALID;
    ke_result registered_light_cid = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, .size = sizeof(ke_directional_light_component), .alignment = _Alignof(ke_directional_light_component), KE_COMPONENT_FIELDS(ke_directional_light_component_fields) }, &light_cid);
    if (registered_light_cid != KE_OK) die_result("component_register", registered_light_cid);

    const ke_mat4 identity = { .m = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 } };

    ke_entity cam = spawn_entity(ecs.ref);
    ke_transform_component *cam_t = attach(ecs.ref, cam, transform_cid);
    *cam_t = (ke_transform_component){ .position = { 1.5f, 1.5f, -3.0f }, .scale = { 1.0f, 1.0f, 1.0f } };
    ke_world_transform_component *cam_w = attach(ecs.ref, cam, world_cid);
    *cam_w = (ke_world_transform_component){ .matrix = identity };
    cam_w->matrix.m[12] = 1.5f;
    cam_w->matrix.m[13] = 1.5f;
    cam_w->matrix.m[14] = -3.0f;
    ke_camera_component *cam_c = attach(ecs.ref, cam, camera_cid);
    *cam_c = (ke_camera_component){ .fov = 60.0f, .near_plane = 0.1f, .far_plane = 100.0f, .cull_mask = UINT32_MAX };

    ke_entity ent = spawn_entity(ecs.ref);
    ke_transform_component *ent_t = attach(ecs.ref, ent, transform_cid);
    *ent_t = (ke_transform_component){ .scale = { 1.0f, 1.0f, 1.0f } };
    ke_world_transform_component *ent_w = attach(ecs.ref, ent, world_cid);
    *ent_w = (ke_world_transform_component){ .matrix = identity };
    ke_mesh_component *ent_m = attach(ecs.ref, ent, mesh_cid);
    *ent_m = (ke_mesh_component){ .mesh = cube_h, .material = mat, .layers = 1 };

    ke_entity sun = spawn_entity(ecs.ref);
    ke_directional_light_component *sun_l = attach(ecs.ref, sun, light_cid);
    *sun_l = (ke_directional_light_component){
        .direction = { -0.4f, -1.0f, -0.3f },
        .color = { 1.0f, 1.0f, 1.0f },
        .intensity = 3.0f,
        .ambient = { 0.03f, 0.03f, 0.04f },
    };

    printf("Drawing a lit cube. Close the window to exit.\n");
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
    renderer_destroy(&render);
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

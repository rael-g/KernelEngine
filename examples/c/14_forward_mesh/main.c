#include <kernel_engine/common/error.h>
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

static void renderer_compose(renderer *r, ke_runtime *rt, ke_ecs *ecs, ke_gpu_device *gpu, ke_gpu_render_target *target)
{
    ke_error *err = NULL;
    r->binder = ke_render_resource_binder_grouped_create(&(ke_render_resource_binder_grouped_params){ .device = gpu, .shader_dir = "shaders" }, &err);
    if (!r->binder.ref) die("resource binder", err);
    r->service = ke_render_service_create(&(ke_render_service_params){
        .device = gpu, .target = target, .ecs = ecs, .shader_dir = "shaders", .binder = r->binder.ref }, &err);
    if (!r->service.ref) die("render service", err);
    ke_render_service *core = r->service.ref;

    ke_ndc_convention ndc = gpu->get_ndc_convention(gpu);
    r->view_space = ke_view_space_rh_create(&err);
    if (!r->view_space.ref) die("view space", err);
    r->camera = ke_render_camera_create(r->view_space.ref, &ndc, &err);
    if (!r->camera.ref) die("camera", err);

    r->scene = ke_render_scene_resolve_create(&(ke_render_scene_resolve_params){ .runtime = rt, .ecs = ecs, .service = core }, &err);
    if (!r->scene.ref) die("scene resolve", err);
    const ke_render_scene_component_ids *ids = r->scene.ref->component_ids(r->scene.ref);

    r->frame = ke_render_frame_create(&(ke_render_frame_params){
        .runtime = rt, .ecs = ecs, .service = core, .camera = r->camera.ref,
        .camera_cid = ids->camera, .world_transform_cid = ids->world_transform,
        .directional_light_cid = ids->directional_light, .ambient_light_cid = ids->ambient_light }, &err);
    if (!r->frame.ref) die("frame", err);
    ke_component_id frame_cid = r->frame.ref->frame_cid(r->frame.ref);

    r->shadow = ke_render_shadow_create(&(ke_render_shadow_params){
        .runtime = rt, .service = core, .device = gpu, .view_space = r->view_space.ref, .ndc = ndc,
        .mesh_cid = ids->mesh, .world_transform_cid = ids->world_transform, .light_cid = ids->directional_light,
        .frame_cid = frame_cid, .output = "shadow" }, &err);
    if (!r->shadow.ref) die("shadow pass", err);
    r->cluster = ke_render_cluster_create(&(ke_render_cluster_params){
        .runtime = rt, .service = core, .device = gpu, .view_space = r->view_space.ref, .camera = r->camera.ref,
        .point_light_cid = ids->point_light, .spot_light_cid = ids->spot_light, .world_transform_cid = ids->world_transform,
        .camera_cid = ids->camera, .frame_cid = frame_cid, .output = "clusters" }, &err);
    if (!r->cluster.ref) die("cluster pass", err);
    r->gbuffer = ke_render_gbuffer_create(&(ke_render_gbuffer_params){
        .runtime = rt, .service = core, .device = gpu, .mesh_cid = ids->mesh, .world_transform_cid = ids->world_transform,
        .camera_cid = ids->camera, .frame_cid = frame_cid, .output = "gbuffer" }, &err);
    if (!r->gbuffer.ref) die("gbuffer pass", err);
    r->deferred = ke_render_deferred_lighting_create(&(ke_render_deferred_lighting_params){
        .runtime = rt, .service = core, .device = gpu, .ibl_enabled = true,
        .camera_cid = ids->camera, .world_transform_cid = ids->world_transform, .skybox_cid = ids->skybox, .frame_cid = frame_cid,
        .gbuffer = "gbuffer", .shadow = "shadow", .clusters = "clusters" }, &err);
    if (!r->deferred.ref) die("deferred lighting pass", err);
    r->tonemap = ke_render_tonemap_create(&(ke_render_tonemap_params){
        .runtime = rt, .service = core, .device = gpu, .frame_cid = frame_cid }, &err);
    if (!r->tonemap.ref) die("tonemap pass", err);
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
    ke_error *err = NULL;

    ke_window_glfw_params wp = {
        .logger = NULL, .input = NULL,
        .title = "c_demo_14 forward mesh", .width = 800, .height = 600,
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

    ke_runtime_params rtp = { 0 };
    ke_runtime_handle rt = ke_runtime_create(ecs.ref, sched.ref, &rtp, &err);
    if (!rt.ref) die("runtime", err);

    renderer render;
    renderer_compose(&render, rt.ref, ecs.ref, gpu.ref, target.ref);
    ke_render_service *core = render.service.ref;

    ke_mesh_handle cube_h = core->upload_mesh(core, "example:cube", cube, sizeof(cube), cube_idx,
                                              sizeof(cube_idx) / sizeof(cube_idx[0]), &err);
    if (cube_h.bits == KE_HANDLE_NONE) die("upload_mesh", err);

    const float orange[4] = { 0.85f, 0.35f, 0.2f, 1.0f };
    ke_material_handle mat = core->create_material(core, "example:orange", orange, 0.0f, 0.5f, KE_TEXTURE_NONE, KE_TEXTURE_NONE,
                                                    KE_ALPHA_MODE_OPAQUE, 0.5f, 1.5f, 0.05f, NULL, &err);
    if (mat.bits == KE_HANDLE_NONE) die("create_material", err);

    ke_component_id transform_cid = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_TRANSFORM, .size = sizeof(ke_transform_component), .alignment = _Alignof(ke_transform_component), KE_COMPONENT_FIELDS(ke_transform_component_fields) }, NULL);
    ke_component_id world_cid     = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_WORLD_TRANSFORM, .size = sizeof(ke_world_transform_component), .alignment = _Alignof(ke_world_transform_component) }, NULL);
    ke_component_id camera_cid    = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_CAMERA, .size = sizeof(ke_camera_component), .alignment = _Alignof(ke_camera_component), KE_COMPONENT_FIELDS(ke_camera_component_fields) }, NULL);
    ke_component_id mesh_cid      = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_MESH, .size = sizeof(ke_mesh_component), .alignment = _Alignof(ke_mesh_component), KE_COMPONENT_FIELDS(ke_mesh_component_fields) }, NULL);
    ke_component_id light_cid     = ecs.ref->component_register(ecs.ref, &(ke_component_params){ .name = KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, .size = sizeof(ke_directional_light_component), .alignment = _Alignof(ke_directional_light_component), KE_COMPONENT_FIELDS(ke_directional_light_component_fields) }, NULL);

    const ke_mat4 identity = { .m = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 } };

    ke_entity cam = ecs.ref->entity_create(ecs.ref);
    ke_transform_component *cam_t = ecs.ref->component_add(ecs.ref, cam, transform_cid);
    *cam_t = (ke_transform_component){ .position = { 1.5f, 1.5f, -3.0f }, .scale = { 1.0f, 1.0f, 1.0f } };
    ke_world_transform_component *cam_w = ecs.ref->component_add(ecs.ref, cam, world_cid);
    *cam_w = (ke_world_transform_component){ .matrix = identity };
    cam_w->matrix.m[12] = 1.5f;
    cam_w->matrix.m[13] = 1.5f;
    cam_w->matrix.m[14] = -3.0f;
    ke_camera_component *cam_c = ecs.ref->component_add(ecs.ref, cam, camera_cid);
    *cam_c = (ke_camera_component){ .fov = 60.0f, .near_plane = 0.1f, .far_plane = 100.0f, .cull_mask = UINT32_MAX };

    ke_entity ent = ecs.ref->entity_create(ecs.ref);
    ke_transform_component *ent_t = ecs.ref->component_add(ecs.ref, ent, transform_cid);
    *ent_t = (ke_transform_component){ .scale = { 1.0f, 1.0f, 1.0f } };
    ke_world_transform_component *ent_w = ecs.ref->component_add(ecs.ref, ent, world_cid);
    *ent_w = (ke_world_transform_component){ .matrix = identity };
    ke_mesh_component *ent_m = ecs.ref->component_add(ecs.ref, ent, mesh_cid);
    *ent_m = (ke_mesh_component){ .mesh = cube_h, .material = mat, .layers = 1 };

    ke_entity sun = ecs.ref->entity_create(ecs.ref);
    ke_directional_light_component *sun_l = ecs.ref->component_add(ecs.ref, sun, light_cid);
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
        win.ref->poll_events(win.ref, NULL);
        double t = now_seconds();
        rt.ref->tick(rt.ref, (float)(t - prev), &err);
        prev = t;
    }

    if (!rt.ref->flush_render(rt.ref, &err)) die("flush render", err);
    renderer_destroy(&render);
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

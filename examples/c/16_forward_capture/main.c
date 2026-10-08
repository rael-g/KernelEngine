#include <kernel_engine/common/error.h>
#include <kernel_engine/math/math.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/gpu/gpu_commands.h>
#include <kernel_engine/render/gpu/gpu_enums.h>
#include <kernel_engine/render/texture_target/gpu_render_target_texture_create.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/module/render_module_create.h>
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

#include <stb_image_write.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void die(const char *msg, ke_error *err)
{
    if (err) { ke_error_fatal(err); }
    ke_error fallback = { .type = &KE_ERROR_GENERAL, .message = msg, .file = __FILE__, .line = __LINE__, .cause = NULL };
    ke_error_fatal(&fallback);
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

enum { WIDTH = 320, HEIGHT = 240, BYTES_PER_TEXEL = 4, FRAMES = 3 };

typedef struct readback
{
    bool done;
    bool ok;
} readback;

static void on_mapped(ke_gpu_buffer buffer, bool ok, void *user)
{
    (void)buffer;
    readback *r = user;
    r->ok = ok;
    r->done = true;
}

static void read_texture(ke_gpu_device *gpu, ke_gpu_texture texture, uint8_t *out_pixels)
{
    ke_error *err = NULL;
    ke_gpu_capabilities caps = { 0 };
    gpu->get_capabilities(gpu, &caps);
    uint32_t align = caps.copy_bytes_per_row_alignment;
    uint32_t padded_row = (WIDTH * BYTES_PER_TEXEL + align - 1) / align * align;

    ke_gpu_buffer staging = gpu->create_buffer(gpu, &(ke_gpu_buffer_params){
        .size = (size_t)padded_row * HEIGHT,
        .usage = KE_GPU_BUFFER_USAGE_COPY_DST | KE_GPU_BUFFER_USAGE_MAP_READ }, &err);
    if (staging == KE_GPU_INVALID_HANDLE) die("staging buffer create failed", err);

    ke_gpu_queue q = gpu->get_default_queue(gpu);
    ke_gpu_command_encoder *enc = gpu->create_command_encoder(gpu);
    if (!enc->copy_texture_to_buffer(enc, texture, 0, 0, 0, staging, 0, padded_row, WIDTH, HEIGHT, &err))
        die("copy to buffer failed", err);
    ke_gpu_command_buffer *cmd = enc->finish(enc);
    enc->destroy(enc);
    ke_gpu_command_buffer *cmds[] = { cmd };
    gpu->queue_submit(gpu, q, cmds, 1);
    cmd->destroy(cmd);

    readback r = { 0 };
    gpu->map_buffer_read(gpu, staging, 0, (size_t)padded_row * HEIGHT, on_mapped, &r);
    while (!r.done) gpu->queue_wait_idle(gpu, q);
    if (!r.ok) die("map for reading failed", NULL);

    const uint8_t *mapped = gpu->map_buffer(gpu, staging, 0, (size_t)padded_row * HEIGHT);
    if (!mapped) die("mapped range unavailable", NULL);
    for (uint32_t y = 0; y < HEIGHT; ++y)
        memcpy(out_pixels + (size_t)y * WIDTH * BYTES_PER_TEXEL, mapped + (size_t)y * padded_row, WIDTH * BYTES_PER_TEXEL);
    gpu->unmap_buffer(gpu, staging);
    gpu->destroy_buffer(gpu, staging);
}

int main(int argc, char **argv)
{
    printf("--- c_demo_16: forward lit cube captured offscreen ---\n");
    ke_error *err = NULL;

    ke_gpu_device_webgpu_params dp = { .logger = NULL, .enable_validation = 1 };
    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&dp, &err);
    if (!gpu.ref) die("gpu device", err);

    ke_gpu_texture texture = gpu.ref->create_texture(gpu.ref, &(ke_gpu_texture_params){
        .width = WIDTH, .height = HEIGHT, .depth_or_array_layers = 1,
        .format = KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM, .dimension = KE_GPU_TEXTURE_DIM_2D,
        .usage = KE_GPU_TEXTURE_USAGE_COLOR_ATTACH | KE_GPU_TEXTURE_USAGE_COPY_SRC,
        .mip_level_count = 1, .sample_count = 1 });
    if (texture == KE_GPU_INVALID_HANDLE) die("texture create failed", NULL);

    ke_gpu_render_target_handle target = ke_gpu_render_target_texture_create(gpu.ref,
        &(ke_gpu_render_target_texture_params){ .texture = texture, .width = WIDTH, .height = HEIGHT,
                                                 .format = KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM }, &err);
    if (!target.ref) die("render target", err);

    ke_ecs_flecs_params ep = { .world_id_base = 0 };
    ke_ecs_handle ecs = ke_ecs_flecs_create(&ep, &err);
    if (!ecs.ref) die("ecs", err);

    ke_scheduler_handle sched = ke_scheduler_enki_create(&err);
    if (!sched.ref) die("scheduler", err);

    ke_runtime_params rtp = { 0 };
    ke_runtime_handle rt = ke_runtime_create(ecs.ref, sched.ref, &rtp, &err);
    if (!rt.ref) die("runtime", err);

    ke_render_module_handle render = ke_render_module_create(rt.ref, ecs.ref, gpu.ref, target.ref, NULL, 1, NULL, NULL, NULL, NULL, NULL, NULL, "shaders", &err);
    if (!render.ref) die("render module", err);
    ke_render_service *core = ke_render_module_core(render.ref);

    ke_mesh_handle cube_h = core->upload_mesh(core, "example:cube", cube, sizeof(cube), cube_idx,
                                              sizeof(cube_idx) / sizeof(cube_idx[0]), &err);
    if (cube_h.bits == KE_HANDLE_NONE) die("upload_mesh", err);

    const float orange[4] = { 0.85f, 0.35f, 0.2f, 1.0f };
    ke_material_handle mat = core->create_material(core, "example:orange", orange, 0.0f, 0.5f, KE_TEXTURE_NONE, KE_TEXTURE_NONE,
                                                    KE_ALPHA_MODE_OPAQUE, 0.5f, 1.5f, 0.05f, NULL, &err);
    if (mat.bits == KE_HANDLE_NONE) die("create_material", err);

    ke_component_id transform_cid = ecs.ref->component_register(ecs.ref, KE_COMPONENT_NAME_TRANSFORM, sizeof(ke_transform_component), KE_COMPONENT_FIELDS(ke_transform_component_fields), NULL);
    ke_component_id world_cid     = ecs.ref->component_register(ecs.ref, KE_COMPONENT_NAME_WORLD_TRANSFORM, sizeof(ke_world_transform_component), NULL, 0, NULL);
    ke_component_id camera_cid    = ecs.ref->component_register(ecs.ref, KE_COMPONENT_NAME_CAMERA,    sizeof(ke_camera_component), KE_COMPONENT_FIELDS(ke_camera_component_fields), NULL);
    ke_component_id mesh_cid      = ecs.ref->component_register(ecs.ref, KE_COMPONENT_NAME_MESH,      sizeof(ke_mesh_component), KE_COMPONENT_FIELDS(ke_mesh_component_fields), NULL);
    ke_component_id light_cid     = ecs.ref->component_register(ecs.ref, KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, sizeof(ke_directional_light_component), KE_COMPONENT_FIELDS(ke_directional_light_component_fields), NULL);

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

    const float dt = 1.0f / 60.0f;
    for (int i = 0; i < FRAMES; ++i)
        if (!rt.ref->tick(rt.ref, dt, &err)) die("tick", err);
    if (!rt.ref->flush_render(rt.ref, &err)) die("flush render", err);

    size_t image_bytes = (size_t)WIDTH * HEIGHT * BYTES_PER_TEXEL;
    uint8_t *pixels = malloc(image_bytes);
    if (!pixels) die("out of memory", NULL);
    read_texture(gpu.ref, texture, pixels);

    size_t lit = 0;
    for (size_t i = 0; i < image_bytes; i += BYTES_PER_TEXEL)
        if (memcmp(pixels + i, pixels, BYTES_PER_TEXEL) != 0) ++lit;
    printf("%zu of %d texels differ from the corner\n", lit, WIDTH * HEIGHT);

    bool written = true;
    if (argc > 1)
    {
        written = stbi_write_png(argv[1], WIDTH, HEIGHT, BYTES_PER_TEXEL, pixels, WIDTH * BYTES_PER_TEXEL) != 0;
        printf("%s %s\n", written ? "wrote" : "failed to write", argv[1]);
    }
    free(pixels);

    render.destroy(render.ref);
    rt.destroy(rt.ref);
    sched.destroy(sched.ref);
    ecs.destroy(ecs.ref);
    target.destroy(target.ref);
    gpu.ref->destroy_texture(gpu.ref, texture);
    gpu.destroy(gpu.ref);

    printf("--- Done ---\n");
    return lit > 0 && written ? 0 : 1;
}

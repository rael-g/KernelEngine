#include "pong.h"

#include <kernel_engine/audio/miniaudio/miniaudio_audio.h>
#include <kernel_engine/audio/module/sound_module.h>
#include <kernel_engine/configuration/configuration_create.h>
#include <kernel_engine/configuration/toml/configuration_toml.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/file_system/std/file_system_std_create.h>
#include <kernel_engine/framework/asset_resolver_create.h>
#include <kernel_engine/framework/engine_node_types.h>
#include <kernel_engine/framework/input_actions_create.h>
#include <kernel_engine/framework/node_types_create.h>
#include <kernel_engine/framework/scene_files_create.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/input/default/input_default_create.h>
#include <kernel_engine/io/pool/io_pool_create.h>
#include <kernel_engine/physics/body2d/body2d_module.h>
#include <kernel_engine/physics/box2d/box2d_physics.h>
#include <kernel_engine/render/binder_grouped/resource_binder_grouped_create.h>
#include <kernel_engine/render/camera/camera_create.h>
#include <kernel_engine/render/cluster/cluster_create.h>
#include <kernel_engine/render/deferred_lighting/deferred_lighting_create.h>
#include <kernel_engine/render/forward/forward_create.h>
#include <kernel_engine/render/frame/frame_create.h>
#include <kernel_engine/render/gbuffer/gbuffer_create.h>
#include <kernel_engine/render/scene/label_resolve_create.h>
#include <kernel_engine/render/scene/scene_resolve_create.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/render/shadow/shadow_create.h>
#include <kernel_engine/render/tonemap/tonemap_create.h>
#include <kernel_engine/render/ui/ui_create.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/task_pool/enki/enki_task_pool.h>
#include <kernel_engine/text/stb_truetype/stb_font.h>
#include <kernel_engine/view/space/view_space_rh_create.h>
#include <kernel_engine/window/glfw/glfw_window.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { PATH_CAPACITY = 1024 };

static const char *const font_candidates[] = {
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
    "C:/Windows/Fonts/arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
};

static void check(const char *what, ke_result result)
{
    if (result == KE_OK) return;
    fprintf(stderr, "%s failed with result code 0x%08x\n", what, (unsigned)result);
    exit(1);
}

static void beside(char *out, const char *exe, const char *name)
{
    const char *slash = strrchr(exe, '/');
    const char *backslash = strrchr(exe, '\\');
    if (backslash && (!slash || backslash > slash)) slash = backslash;
    int dir = slash ? (int)(slash - exe) : 1;
    snprintf(out, PATH_CAPACITY, "%.*s/%s", dir, slash ? exe : ".", name);
}

static const char *find_font(void)
{
    for (size_t i = 0; i < sizeof font_candidates / sizeof font_candidates[0]; ++i)
    {
        FILE *f = fopen(font_candidates[i], "rb");
        if (!f) continue;
        fclose(f);
        return font_candidates[i];
    }
    return NULL;
}

static double now_seconds(void)
{
    struct timespec t;
    timespec_get(&t, TIME_UTC);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

typedef struct frame_input
{
    ke_input         *input;
    ke_input_actions *actions;
} frame_input;

static ke_result read_input(ke_system_ctx *ctx, void *user_data, float dt)
{
    (void)ctx;
    (void)dt;
    frame_input *in = user_data;
    in->input->update(in->input);
    ke_input_snapshot snapshot;
    in->input->get_snapshot(in->input, &snapshot);
    return in->actions->evaluate(in->actions, &snapshot);
}

typedef struct first_scene
{
    pong_game *game;
    char       path[PATH_CAPACITY];
} first_scene;

static ke_result load_first_scene(ke_system_ctx *ctx, void *user_data, float dt)
{
    (void)dt;
    first_scene *first = user_data;
    return pong_load_scene(first->game, ctx->commands, first->path);
}

typedef struct renderer
{
    ke_render_resource_binder_handle   binder;
    ke_render_service_handle           service;
    ke_view_space_handle               view_space;
    ke_render_camera_handle            camera;
    ke_render_scene_resolve_handle     scene;
    ke_render_frame_handle             frame;
    ke_render_shadow_handle            shadow;
    ke_render_cluster_handle           cluster;
    ke_render_gbuffer_handle           gbuffer;
    ke_render_deferred_lighting_handle deferred;
    ke_render_forward_handle           forward;
    ke_render_tonemap_handle           tonemap;
    ke_render_ui_handle                ui;
    ke_render_label_resolve_handle     labels;
} renderer;

static void renderer_compose(renderer *r, ke_runtime *rt, ke_ecs *ecs, ke_gpu_device *gpu, ke_gpu_render_target *target, ke_io *io,
                             ke_asset_resolver *assets, const char *shader_dir, ke_vec4 clear_color)
{
    check("resource binder", ke_render_resource_binder_grouped_create(&(ke_render_resource_binder_grouped_params){ .device = gpu, .shader_dir = shader_dir, .io = io }, &r->binder));
    check("render service", ke_render_service_create(gpu, target, ecs, io, r->binder.ref,
        &(ke_render_service_config){ .shader_dir = shader_dir, .color_format = KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT, .depth_format = KE_GPU_TEXTURE_FORMAT_D32_FLOAT, .clear_color = clear_color }, &r->service));
    ke_render_service *core = r->service.ref;
    check("view space", ke_view_space_rh_create(&r->view_space));
    check("camera", ke_render_camera_create(r->view_space.ref, gpu, &r->camera));
    check("scene resolve", ke_render_scene_resolve_create(&(ke_render_scene_resolve_params){ .runtime = rt, .ecs = ecs, .service = core }, &r->scene));
    check("frame", ke_render_frame_create(&(ke_render_frame_params){ .runtime = rt, .ecs = ecs, .service = core, .camera = r->camera.ref, .scene = r->scene.ref }, &r->frame));
    check("shadow pass", ke_render_shadow_create(&(ke_render_shadow_params){
        .scene = r->scene.ref, .frame = r->frame.ref, .runtime = rt, .service = core, .device = gpu, .view_space = r->view_space.ref, .output = "shadow" }, &r->shadow));
    check("cluster pass", ke_render_cluster_create(rt, core, gpu, r->view_space.ref, r->camera.ref, r->scene.ref, r->frame.ref, "clusters", NULL, &r->cluster));
    check("gbuffer pass", ke_render_gbuffer_create(&(ke_render_gbuffer_params){
        .scene = r->scene.ref, .frame = r->frame.ref, .runtime = rt, .service = core, .device = gpu, .output = "gbuffer" }, &r->gbuffer));
    check("deferred lighting pass", ke_render_deferred_lighting_create(&(ke_render_deferred_lighting_params){
        .scene = r->scene.ref, .frame = r->frame.ref, .runtime = rt, .service = core, .device = gpu, .ibl_enabled = true,
        .gbuffer = "gbuffer", .shadow = "shadow", .clusters = "clusters" }, &r->deferred));
    check("forward pass", ke_render_forward_create(&(ke_render_forward_params){
        .runtime = rt, .service = core, .device = gpu, .ibl_enabled = true, .scene = r->scene.ref, .frame = r->frame.ref, .shadow = "shadow", .clusters = "clusters" }, &r->forward));
    check("tonemap pass", ke_render_tonemap_create(&(ke_render_tonemap_params){ .runtime = rt, .service = core, .device = gpu, .frame = r->frame.ref }, &r->tonemap));
    check("ui pass", ke_render_ui_create(&(ke_render_ui_params){ .runtime = rt, .ecs = ecs, .service = core, .device = gpu, .frame = r->frame.ref }, &r->ui));
    check("label resolve", ke_render_label_resolve_create(&(ke_render_label_resolve_params){
        .runtime = rt, .service = core, .ui = r->ui.ref, .resolver = assets, .scene = r->scene.ref }, &r->labels));
}

static void renderer_destroy(renderer *r)
{
    r->labels.destroy(r->labels.ref);
    r->ui.destroy(r->ui.ref);
    r->tonemap.destroy(r->tonemap.ref);
    r->forward.destroy(r->forward.ref);
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

static ke_gpu_present_mode present_mode_of(const char *name)
{
    if (strcmp(name, "mailbox") == 0) return KE_GPU_PRESENT_MODE_MAILBOX;
    if (strcmp(name, "immediate") == 0) return KE_GPU_PRESENT_MODE_IMMEDIATE;
    return KE_GPU_PRESENT_MODE_FIFO;
}

int main(int argc, char **argv)
{
    char project_dir[PATH_CAPACITY], shader_dir[PATH_CAPACITY], project_file[PATH_CAPACITY];
    beside(project_dir, argv[0], "pong");
    beside(shader_dir, argv[0], "shaders");
    snprintf(project_file, sizeof project_file, "%s/Project", project_dir);

    pong_game game = { .font = argc > 1 ? argv[1] : find_font() };
    if (!game.font)
    {
        fprintf(stderr, "no TrueType font found; pass one as the first argument\n");
        return 1;
    }

    ke_task_pool_handle pool = { 0 };
    check("task pool", ke_task_pool_enki_create(NULL, &pool));
    ke_file_system_handle files = { 0 };
    check("file system", ke_file_system_std_create(NULL, &files));
    ke_io_handle io = { 0 };
    check("io", ke_io_pool_create(pool.ref, files.ref, &io));

    ke_configuration_handle config = { 0 };
    check("configuration", ke_configuration_create(&config));
    ke_configuration_source_handle toml = { 0 };
    check("toml source", ke_configuration_toml_create(io.ref, &toml));
    check("project file", toml.ref->load(toml.ref, config.ref, project_file));
    ke_configuration *cfg = config.ref;

    ke_input_handle input = { 0 };
    check("input", ke_input_create(&input));
    ke_window_glfw_config window_config = {
        .title = cfg->get_string(cfg, "runtime.window", "title", "Pong"),
        .width = (int32_t)cfg->get_int(cfg, "runtime.window", "width", 960),
        .height = (int32_t)cfg->get_int(cfg, "runtime.window", "height", 540),
        .fullscreen = cfg->get_bool(cfg, "runtime.window", "fullscreen", false),
    };
    ke_window_handle window = { 0 };
    check("window", ke_window_glfw_create(input.ref, &window_config, &window));

    ke_ecs_handle ecs = { 0 };
    check("ecs", ke_ecs_flecs_create(NULL, &ecs));
    ke_runtime_handle rt = { 0 };
    check("runtime", ke_runtime_create(ecs.ref, pool.ref, NULL, &rt));

    ke_gpu_device_handle gpu = { 0 };
    check("gpu device", ke_gpu_device_webgpu_create(NULL, &(ke_gpu_device_webgpu_config){ 0 }, &gpu));
    ke_gpu_render_target_handle target = { 0 };
    check("window target", ke_gpu_render_target_webgpu_window_create(gpu.ref, window.ref,
        &(ke_gpu_render_target_webgpu_window_config){ .present_mode = present_mode_of(cfg->get_string(cfg, "runtime.renderer", "present_mode", "fifo")) }, &target));

    ke_font_loader_handle fonts = { 0 };
    check("font loader", ke_font_loader_stb_create(io.ref, &fonts));
    ke_asset_resolver_handle assets = { 0 };
    check("asset resolver", ke_asset_resolver_create(NULL, fonts.ref, project_dir, io.ref, &assets));

    ke_scene_tree_handle tree = { 0 };
    check("scene tree", ke_scene_tree_create(ecs.ref, rt.ref, &tree));

    const ke_vec4 clear_color = {
        (float)cfg->get_double(cfg, "render", "clear_color.0", 0.0),
        (float)cfg->get_double(cfg, "render", "clear_color.1", 0.0),
        (float)cfg->get_double(cfg, "render", "clear_color.2", 0.0),
        (float)cfg->get_double(cfg, "render", "clear_color.3", 1.0),
    };
    renderer render;
    renderer_compose(&render, rt.ref, ecs.ref, gpu.ref, target.ref, io.ref, assets.ref, shader_dir, clear_color);

    ke_physics_2d_handle physics = { 0 };
    check("physics", ke_physics_2d_box2d_create(&(ke_physics_2d_box2d_config){
        .gravity_x = (float)cfg->get_double(cfg, "runtime.physics_2d", "gravity_x", 0.0),
        .gravity_y = (float)cfg->get_double(cfg, "runtime.physics_2d", "gravity_y", 0.0) }, &physics));
    ke_physics_body2d_module_handle bodies = { 0 };
    check("body2d module", ke_physics_body2d_module_create(&(ke_physics_body2d_module_params){
        .runtime = rt.ref, .ecs = ecs.ref, .physics = physics.ref, .scene_tree = tree.ref }, &bodies));

    ke_audio_handle audio = { 0 };
    check("audio", ke_audio_miniaudio_create(io.ref, &audio));
    ke_sound_module_handle sounds = { 0 };
    check("sound module", ke_sound_module_create(rt.ref, ecs.ref, audio.ref, &(ke_sound_module_config){ .root = project_dir }, &sounds));

    ke_input_actions_handle actions = { 0 };
    check("input actions", ke_input_actions_create(cfg, NULL, &actions));
    ke_node_types_handle types = { 0 };
    check("node types", ke_node_types_create(rt.ref, ecs.ref, tree.ref, actions.ref, &types));
    ke_scene_files_handle scenes = { 0 };
    check("scene files", ke_scene_files_create(ecs.ref, types.ref, assets.ref, io.ref, &scenes));

    for (size_t i = 0; i < KE_ENGINE_NODE_TYPE_COUNT; ++i)
    {
        ke_component_id type = KE_COMPONENT_INVALID;
        check(ke_engine_node_types[i].name, types.ref->register_type(types.ref, &ke_engine_node_types[i], &type));
    }

    game.ecs = ecs.ref;
    game.types = types.ref;
    game.scenes = scenes.ref;
    game.actions = actions.ref;
    check("pong types", pong_register(&game));

    frame_input in = { .input = input.ref, .actions = actions.ref };
    ke_system_id input_system = 0;
    check("input system", rt.ref->register_system(rt.ref, &(ke_runtime_system_params){
        .name = "pong.input", .phase = KE_PHASE_PRE_UPDATE, .user_data = &in, .execute = read_input, .exclusive = true }, &input_system));
    first_scene first = { .game = &game };
    snprintf(first.path, sizeof first.path, "res://scenes/%s.scene.toml", cfg->get_string(cfg, "project", "default_scene", "Menu"));
    ke_system_id first_system = 0;
    check("first scene system", rt.ref->register_system(rt.ref, &(ke_runtime_system_params){
        .name = "pong.first_scene", .phase = KE_PHASE_STARTUP, .user_data = &first, .execute = load_first_scene, .exclusive = true }, &first_system));

    double previous = now_seconds();
    while (!window.ref->should_close(window.ref) && !game.quit_requested)
    {
        window.ref->poll_events(window.ref);
        double current = now_seconds();
        check("tick", rt.ref->tick(rt.ref, (float)(current - previous)));
        previous = current;
    }
    check("flush render", rt.ref->flush_render(rt.ref));
    rt.ref->unload_modules(rt.ref);

    scenes.destroy(scenes.ref);
    types.destroy(types.ref);
    actions.destroy(actions.ref);
    sounds.destroy(sounds.ref);
    audio.destroy(audio.ref);
    bodies.destroy(bodies.ref);
    physics.destroy(physics.ref);
    renderer_destroy(&render);
    tree.destroy(tree.ref);
    assets.destroy(assets.ref);
    fonts.destroy(fonts.ref);
    rt.destroy(rt.ref);
    ecs.destroy(ecs.ref);
    target.destroy(target.ref);
    gpu.destroy(gpu.ref);
    window.destroy(window.ref);
    input.destroy(input.ref);
    toml.destroy(toml.ref);
    config.destroy(config.ref);
    io.destroy(io.ref);
    files.destroy(files.ref);
    pool.destroy(pool.ref);
    return 0;
}

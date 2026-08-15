#pragma once

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/render/ui/ui_create.h>
#include <kernel_engine/text/font.h>
#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/framework/world.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

struct ke_logger;

typedef struct ke_render_module ke_render_module;

typedef struct ke_render_module_handle
{
    ke_render_module *ref;
    void (*destroy)(ke_render_module *self);
} ke_render_module_handle;

typedef struct ke_render_cluster_params
{
    uint32_t grid_x;                  // screen-tile columns; 0 = default (32)
    uint32_t grid_y;                  // screen-tile rows; 0 = default (18)
    uint32_t grid_z;                  // depth slices; 0 = default (24)
    uint32_t max_lights_per_cluster;   // per-froxel index-list cap; 0 = default (256)
} ke_render_cluster_params;

typedef struct ke_render_feature_params
{
    ke_bool enable_shadows; // 0 = no shadow pass, no shadow map, no shadow shader bindings
    ke_bool enable_ibl;     // 0 = no IBL sampling in materials (IndirectIBL contribution); skybox rendering is unaffected
} ke_render_feature_params;

KE_RENDER_CORE_API ke_render_module_handle
ke_render_module_create(ke_runtime *runtime, ke_ecs *ecs, ke_gpu_device *device,
                        ke_world *world, ke_bool default_passes, struct ke_logger *logger,
                        ke_asset_resolver *asset_resolver,
                        const ke_render_cluster_params *cluster_params,
                        const ke_render_feature_params *feature_params,
                        const char *shader_dir, ke_error **out_error);

KE_RENDER_CORE_API bool
ke_render_register_scene_apply(ke_ecs *ecs, ke_world *world);

KE_RENDER_CORE_API ke_render_service *ke_render_module_core(ke_render_module *module);

/**
 * Registers a font's glyph table (see ke_render_ui.load_font), deduped by
 * @p key. KE_UI_FONT_NONE on failure. Queuing a UI quad no longer goes
 * through the render module — game code attaches the "ui_quad" ECS component
 * directly, resolved by the "render.ui" pass the same way every other
 * render-phase pass consumes sim-written data.
 * @param key [utf8]
 * @param glyphs [borrowed,array_of:glyph_count]
 */
KE_RENDER_CORE_API ke_ui_font_handle
ke_render_module_load_font(ke_render_module *module, const char *key,
                           ke_texture_handle atlas, const ke_glyph_metrics *glyphs,
                           uint32_t glyph_count, float line_height, float ascent,
                           ke_error **out_error);

#ifdef __cplusplus
}
#endif

#ifndef KERNEL_ENGINE_RENDER_MODULE_RENDER_MODULE_CREATE_H_
#define KERNEL_ENGINE_RENDER_MODULE_RENDER_MODULE_CREATE_H_

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/render/shadow/shadow_create.h>
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
    uint32_t grid_x;
    uint32_t grid_y;
    uint32_t grid_z;
    uint32_t max_lights_per_cluster;
} ke_render_cluster_params;

typedef struct ke_render_feature_params
{
    bool    enable_shadows;
    bool    enable_ibl;
} ke_render_feature_params;

/// The asset_resolver argument is borrowed and may be NULL. It turns an authored
/// path into an uploaded texture; where the host wires none, a sprite that names a
/// file draws untextured instead of failing the load. The binder argument is borrowed
/// and must outlive the module; NULL selects a grouped resource binder the module owns.
KE_RENDER_CORE_API ke_render_module_handle
ke_render_module_create(ke_runtime *runtime, ke_ecs *ecs, ke_gpu_device *device,
                        ke_gpu_render_target *target,
                        ke_world *world, bool default_passes, struct ke_logger *logger,
                        ke_asset_resolver *asset_resolver,
                        const ke_render_cluster_params *cluster_params,
                        const ke_render_feature_params *feature_params,
                        const ke_render_shadow_params *shadow_params,
                        ke_view_space *view_space,
                        ke_render_resource_binder *binder,
                        const char *shader_dir, ke_error **out_error);

KE_RENDER_CORE_API bool
ke_render_register_scene_apply(ke_ecs *ecs, ke_world *world);

KE_RENDER_CORE_API ke_render_service *ke_render_module_core(ke_render_module *module);

/**
 * Registers a font's glyph table (see ke_render_ui.load_font), deduped by
 * @p key. KE_UI_FONT_NONE on failure.
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

#endif

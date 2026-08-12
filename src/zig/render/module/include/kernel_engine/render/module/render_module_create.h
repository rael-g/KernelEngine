#pragma once

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

// Clustered-forward froxel grid + per-froxel light-list shape. These are
// workload-tuning values, not engine-imposed limits: a 0 field means "use the
// engine's default" (32x18x24 grid, 256 lights/froxel), but any caller running
// a denser scene than the default sweet spot can raise them — the engine never
// silently caps a scene's fidelity without a way to opt out.
typedef struct ke_render_cluster_params
{
    uint32_t grid_x;                  // screen-tile columns; 0 = default (32)
    uint32_t grid_y;                  // screen-tile rows; 0 = default (18)
    uint32_t grid_z;                  // depth slices; 0 = default (24)
    uint32_t max_lights_per_cluster;   // per-froxel index-list cap; 0 = default (256)
} ke_render_cluster_params;

// Which optional render features actually exist for this module instance. A
// game with no shadows must have no shadow code, shader, or GPU resource — not
// a disabled branch, not an unused embed. NULL (or a zeroed struct) means "use
// the engine defaults", which today preserve prior behavior (shadows on).
// More fields (enable_ibl, enable_bloom, ...) land here as each feature's
// opt-in gets threaded through, following the same shape as enable_shadows.
typedef struct ke_render_feature_params
{
    ke_bool enable_shadows; // 0 = no shadow pass, no shadow map, no shadow shader bindings
    ke_bool enable_ibl;     // 0 = no IBL sampling in materials (IndirectIBL contribution); skybox rendering is unaffected
} ke_render_feature_params;

// Installs the render path into a runtime: builds the render core over the
// shared ecs + a caller-created GPU device. No pass is imposed — when
// default_passes is non-zero it registers the conventional chain (begin → clear
// → forward → end) as KE_PHASE_RENDER systems, ordered by the runtime via the
// backbuffer tag-cid; otherwise the game wires its own passes. The app drives it
// by ticking the runtime. Inputs are borrowed (the device stays caller-owned)
// and must outlive the handle; ref is NULL on failure. `world` registers this
// domain's own [entity.components.X] scene-file apply callbacks (camera, mesh,
// directional/point/spot light) against the caller's ke_world; NULL is valid
// whenever the caller has no ke_world (populating the ECS directly rather than
// through ke_scene_loader), since nothing will ever ask for those callbacks.
// `logger` is optional (NULL is valid) — when present, the module routes its
// own runtime diagnostics (e.g. a scene exceeding a fixed resource cap) through
// it instead of staying silent. `cluster_params` and `feature_params` are optional (NULL
// = all defaults). `shader_dir` is required — an absolute path to the
// directory every pass's build-time-compiled shaders were installed into (see
// ke_render_service_create); forwarded to the render core unchanged.
KE_RENDER_CORE_API ke_render_module_handle
ke_render_module_create(ke_runtime *runtime, ke_ecs *ecs, ke_gpu_device *device,
                        ke_world *world, ke_bool default_passes, struct ke_logger *logger,
                        const ke_render_cluster_params *cluster_params,
                        const ke_render_feature_params *feature_params,
                        const char *shader_dir, ke_error **out_error);

// Registers render's own cids + [entity.components.X] scene-file apply
// callbacks (camera/mesh/directional_light/point_light/spot_light/ambient_light/
// skybox) against `world`, with no GPU device involved. ke_render_module_create
// calls this itself when given a world; a caller that only needs the ECS
// schema populated for ke_scene_loader (e.g. a headless test, or a game
// wiring its own render passes without the default chain) can call it
// directly. Returns false if either argument is NULL.
KE_RENDER_CORE_API bool
ke_render_register_scene_apply(ke_ecs *ecs, ke_world *world);

// Borrows the render core the module owns — used to upload meshes and declare
// resources. Valid for the module's lifetime; the caller must not destroy it.
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

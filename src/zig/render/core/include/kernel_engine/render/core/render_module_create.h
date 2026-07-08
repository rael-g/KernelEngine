#pragma once

#include <kernel_engine/render/core/render_core_create.h>
#include <kernel_engine/runtime/runtime.h>
#include <stdint.h>

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
// and must outlive the handle; ref is NULL on failure. `logger` is optional
// (NULL is valid) — when present, the module routes its own runtime
// diagnostics (e.g. a scene exceeding a fixed resource cap) through it instead
// of staying silent. `cluster_params` and `feature_params` are optional (NULL
// = all defaults).
KE_RENDER_CORE_API ke_render_module_handle
ke_render_module_create(ke_runtime *runtime, ke_ecs *ecs, ke_gpu_device *device,
                        ke_bool default_passes, struct ke_logger *logger,
                        const ke_render_cluster_params *cluster_params,
                        const ke_render_feature_params *feature_params, ke_error **out_error);

// Borrows the render core the module owns — used to upload meshes and declare
// resources. Valid for the module's lifetime; the caller must not destroy it.
KE_RENDER_CORE_API ke_render_core *ke_render_module_core(ke_render_module *module);

// Queues a screen-space UI quad for this frame, drawn after tonemap so it
// composites over the rendered scene. Coordinates are pixels (top-left
// origin); uv selects a region of `texture` (KE_TEXTURE_NONE = built-in white,
// so a flat-color quad just samples white*color); color is premultiplied
// alpha RGBA. Call from any render-phase system body, before the "render.ui"
// pass runs (the module orders it last). Silently dropped past the per-frame
// quad/batch limits. Owned by the module, not the render core: UI overlay is
// a rendering feature (its own pipeline, shaders, batching state) like
// tonemap/forward/shadow, not core machinery.
KE_RENDER_CORE_API void
ke_render_module_ui_quad(ke_render_module *module, ke_texture_handle texture,
                         float dst_x, float dst_y, float dst_w, float dst_h,
                         float u0, float v0, float u1, float v1,
                         float r, float g, float b, float a);

#ifdef __cplusplus
}
#endif

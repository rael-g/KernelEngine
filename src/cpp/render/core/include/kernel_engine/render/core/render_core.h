#ifndef KERNEL_ENGINE_RENDER_CORE_H_
#define KERNEL_ENGINE_RENDER_CORE_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/world/system.h>
#include <kernel_engine/kernel/common/handles.h>
#include <kernel_engine/render/core/render_core_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── Native System Descriptor Factories ────────────────────────────────────────
// These produce `ke_system_params` that wrappers register with `ke_world->add_system(...)`
// (or via a managed scheduler that calls `update()` directly). They are the extended ABI
// the C# `Render.Core` wrapper assembly consumes to expose the built-in render systems.

KE_RENDER_CORE_API void ke_render_core_mesh_system_describe(uint32_t mesh_cid, uint32_t transform_cid, struct ke_system_params* out_params);
KE_RENDER_CORE_API void ke_render_core_light_system_describe(uint32_t light_cid, uint32_t point_cid, uint32_t spot_cid, uint32_t transform_cid, struct ke_system_params* out_params);
KE_RENDER_CORE_API void ke_render_core_camera_system_describe(uint32_t camera_cid, uint32_t transform_cid, struct ke_system_params* out_params);
KE_RENDER_CORE_API void ke_render_core_shadow_system_describe(uint32_t light_cid, uint32_t mesh_cid, uint32_t transform_cid, struct ke_system_params* out_params);
KE_RENDER_CORE_API void ke_render_core_skybox_system_describe(uint32_t skybox_cid, struct ke_system_params* out_params);

/**
 * @brief Sets the shadow map handle on a shadow system descriptor (after GPU init on ke.render).
 */
KE_RENDER_CORE_API void ke_render_core_shadow_system_set_map(struct ke_system_params* params, ke_shadow_map_handle handle);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_CORE_H_

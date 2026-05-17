#ifndef KERNEL_ENGINE_RENDER_CORE_H_
#define KERNEL_ENGINE_RENDER_CORE_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/render/core/render_core_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_render_core_systems_params {
    uint32_t mesh_cid;
    uint32_t transform_cid;
    uint32_t light_cid;
    uint32_t point_cid;
    uint32_t spot_cid;
    uint32_t camera_cid;
    uint32_t skybox_cid;
} ke_render_core_systems_params;

/**
 * @brief Registers the default native render systems to a world.
 * These systems populate the frame packet with rendering commands from the ECS.
 */
KE_RENDER_CORE_API ke_result ke_render_core_register_default_systems(
    struct ke_world* world,
    struct ke_render* render,
    const ke_render_core_systems_params* params);

/**
 * @brief Sets the shadow map handle on a shadow system descriptor.
 */
KE_RENDER_CORE_API void ke_render_core_shadow_system_set_map(struct ke_system_params* params, ke_shadow_map_handle handle);

// ── Native System Descriptor Factories ────────────────────────────────────────

KE_RENDER_CORE_API void ke_render_core_mesh_system_describe(uint32_t mesh_cid, uint32_t transform_cid, struct ke_system_params* out_params);
KE_RENDER_CORE_API void ke_render_core_light_system_describe(uint32_t light_cid, uint32_t point_cid, uint32_t spot_cid, uint32_t transform_cid, struct ke_system_params* out_params);
KE_RENDER_CORE_API void ke_render_core_camera_system_describe(uint32_t camera_cid, uint32_t transform_cid, struct ke_system_params* out_params);
KE_RENDER_CORE_API void ke_render_core_shadow_system_describe(uint32_t light_cid, uint32_t mesh_cid, uint32_t transform_cid, struct ke_system_params* out_params);
KE_RENDER_CORE_API void ke_render_core_skybox_system_describe(uint32_t skybox_cid, struct ke_system_params* out_params);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_CORE_H_

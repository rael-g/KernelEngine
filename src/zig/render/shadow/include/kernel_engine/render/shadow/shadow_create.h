#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/types.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/view/view_space.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_SHADOW_EXPORT
        #define KE_RENDER_SHADOW_API __declspec(dllexport)
    #elif defined(KE_RENDER_SHADOW_STATIC)
        #define KE_RENDER_SHADOW_API
    #else
        #define KE_RENDER_SHADOW_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_SHADOW_API __attribute__((visibility("default")))
#endif

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_render_shadow ke_render_shadow;

    /**
     * Shape of the directional shadow map. Every field is a workload choice, not
     * a property of the algorithm: a scene larger than `extent` loses shadows
     * outside it, and a caster farther than `light_distance` stops casting.
     */
    typedef struct ke_render_shadow_params
    {
        /// Edge of the square shadow map, in texels. 0 takes the default.
        uint32_t resolution;
        /// How far back along the light the shadow camera sits. 0 takes the default.
        float    light_distance;
        /// Width and height of the shadowed area, in world units. 0 takes the default.
        float    extent;
        /// Near plane of the shadow camera. 0 takes the default.
        float    near_plane;
        /// Far plane of the shadow camera. 0 takes the default.
        float    far_plane;
    } ke_render_shadow_params;

    typedef struct ke_render_shadow_handle
    {
        ke_render_shadow *ref;
        void (*destroy)(ke_render_shadow *self);
    } ke_render_shadow_handle;

    KE_RENDER_SHADOW_API ke_render_shadow_handle ke_render_shadow_create(
        ke_runtime *runtime, ke_render_service *core, ke_gpu_device *device,
        ke_ndc_convention ndc, ke_view_space *view_space, ke_bool enabled,
        ke_component_id mesh_cid, ke_component_id world_transform_cid,
        ke_component_id light_cid, ke_component_id frame_cid,
        const ke_render_shadow_params *params,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif

#ifndef KERNEL_ENGINE_RENDER_SHADOW_SHADOW_CREATE_H_
#define KERNEL_ENGINE_RENDER_SHADOW_SHADOW_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/context.h>
#include <stdbool.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/view/view_space.h>
#include <kernel_engine/module/module.h>

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

    /** [bag]
     * The shape of the directional shadow pass's map. A scene larger than
     * `extent` loses shadows outside it, and a caster farther than `light_distance` stops
     * casting.
     */
    typedef struct ke_render_shadow_config
    {
        /// Edge of the square shadow map, in texels.
        uint32_t resolution;
        /// How far back along the light the shadow camera sits.
        float    light_distance;
        /// Width and height of the shadowed area, in world units.
        float    extent;
        /// Near plane of the shadow camera.
        float    near_plane;
        /// Far plane of the shadow camera.
        float    far_plane;
    } ke_render_shadow_config;

    /// Makes the directional shadow pass. Attached, it publishes the shadow map and the light's
    /// view-projection in the render prepare set, and declares the pass that draws the casters into the
    /// map in the render queue set.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param config [borrowed] The map's shape; Required; every field is read as given.
    /// @param out_module [out] Receives the pass; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the context, a part the pass uses or @p config is
    ///         NULL; the code of the GPU object that could not be made.
    KE_RENDER_SHADOW_API ke_result ke_render_shadow_create(
        const ke_render_context *context, const ke_render_shadow_config *config, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif

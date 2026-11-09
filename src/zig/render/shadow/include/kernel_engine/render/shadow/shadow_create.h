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

    /** [defaults] The shadow map's shape a caller gets when it sets nothing. */
    static const ke_render_shadow_config ke_render_shadow_config_defaults = {
        .resolution = 1024,
        .light_distance = 25.0f,
        .extent = 20.0f,
        .near_plane = 0.1f,
        .far_plane = 50.0f,
    };

    /// [owner]
    typedef struct ke_render_shadow_handle
    {
        ke_render_shadow *ref;
        void (*destroy)(ke_render_shadow *self);
    } ke_render_shadow_handle;

    /// Registers the pass's render-phase system. A missing runtime, service, device or view space
    /// fails as an invalid argument.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param config [borrowed,optional] The map's shape; NULL selects the defaults.
    /// @param out_resources [out] Receives the ids of the map and the light it writes; every id
    ///                      KE_COMPONENT_INVALID on failure.
    /// @param out_shadow [out] Receives the handle; left zeroed on failure.
    KE_RENDER_SHADOW_API ke_result ke_render_shadow_create(
        const ke_render_context *context, const ke_render_shadow_config *config, ke_render_shadow_resources *out_resources, ke_render_shadow_handle *out_shadow);

#ifdef __cplusplus
}
#endif

#endif

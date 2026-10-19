#ifndef KERNEL_ENGINE_RENDER_SHADOW_SHADOW_CREATE_H_
#define KERNEL_ENGINE_RENDER_SHADOW_SHADOW_CREATE_H_

#include <kernel_engine/common/error.h>
#include <stdbool.h>
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
     * What the directional shadow pass draws and the shape of its map. A scene larger than
     * `extent` loses shadows outside it, and a caster farther than `light_distance` stops
     * casting. The names are copied.
     */
    typedef struct ke_render_shadow_params
    {
        ke_runtime        *runtime;    ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service;    ///< Holds the resources it writes; borrowed.
        ke_gpu_device     *device;     ///< Borrowed.
        ke_view_space     *view_space; ///< Builds the light's view and projection; borrowed.
        ke_ndc_convention  ndc;
        ke_component_id    mesh_cid;
        ke_component_id    world_transform_cid;
        ke_component_id    light_cid;
        ke_component_id    frame_cid;
        /// [utf8] The shadow group it writes: the map under the group's own name, and the
        /// light and depth under the suffixes of kernel_engine/render/resource_groups.h.
        const char *output;
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

    /// Registers the pass's render-phase system. A missing runtime, service, device, view space
    /// or output fails as an invalid argument; the handle's ref is NULL on failure.
    KE_RENDER_SHADOW_API ke_render_shadow_handle ke_render_shadow_create(
        const ke_render_shadow_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif

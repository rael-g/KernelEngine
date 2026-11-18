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

    struct ke_settings;

    /// Makes the directional shadow pass. Attached, it publishes the shadow map and the light's
    /// view-projection in the render prepare set, and declares the pass that draws the casters into the
    /// map in the render queue set.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param settings [borrowed] Read once; each absent key takes its default. `resolution`, an
    ///        integer, 1024: edge of the square map in texels. `light_distance`, 25: how far back along
    ///        the light the shadow camera sits. `extent`, 20: width and height of the shadowed area in
    ///        world units; a scene larger than it loses shadows outside it. `near_plane`, 0.1, and
    ///        `far_plane`, 50: the shadow camera's planes.
    /// @param out_module [out] Receives the pass; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the context, a part the pass uses or @p settings
    ///         is NULL, a setting is unknown, of another type or out of its range, or the near plane is
    ///         not before the far one; the code of the GPU object that could not be made.
    KE_RENDER_SHADOW_API ke_result ke_render_shadow_create(
        const ke_render_context *context, struct ke_settings *settings, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif

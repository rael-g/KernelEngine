#ifndef KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_CREATE_H_

#include <kernel_engine/render/assets.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/extraction.h>

#ifndef KE_RENDER_SCENE_API
    #if defined(_WIN32) || defined(__CYGWIN__)
        #ifdef KE_RENDER_SCENE_EXPORT
            #define KE_RENDER_SCENE_API __declspec(dllexport)
        #elif defined(KE_RENDER_SCENE_STATIC)
            #define KE_RENDER_SCENE_API
        #else
            #define KE_RENDER_SCENE_API __declspec(dllimport)
        #endif
    #else
        #define KE_RENDER_SCENE_API __attribute__((visibility("default")))
    #endif
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /// Registers the scene's render components in the main world and in the render world, and a copy of
    /// each in the extraction. Its systems come from ke_render_scene_resolve_systems_create.
    /// @param main       The main world; borrowed, must outlive it.
    /// @param render     The render world; borrowed, must outlive it.
    /// @param extraction Copies each component from main into render; borrowed, must outlive it.
    /// @param service    Uploads the meshes, materials and textures; borrowed, must outlive it.
    /// @param assets [optional] Makes the texture of the image a sprite names; borrowed. Without them a sprite
    ///        draws untextured.
    /// @param out_resolve [out] Receives the handle; left zeroed on failure, and the component types
    ///                    registered before the failure stay registered.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL part; the code of the world or the extraction
    ///         that refused a component.
    KE_RENDER_SCENE_API ke_result ke_render_scene_resolve_create(
        ke_ecs *main, ke_ecs *render, ke_extraction *extraction, ke_render_service *service, ke_render_assets *assets,
        ke_render_scene_resolve_handle *out_resolve);

#ifdef __cplusplus
}
#endif

#endif

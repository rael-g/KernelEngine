#ifndef KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_CREATE_H_

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/runtime/runtime.h>

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

    /// [bag] What the scene resolve needs to register the components and upload what they name.
    typedef struct ke_render_scene_resolve_params
    {
        ke_runtime        *runtime;  ///< Registers the resolve systems; borrowed, must outlive it.
        ke_ecs            *ecs;      ///< Registers the components; borrowed.
        ke_render_service *service;  ///< Uploads the meshes, materials and textures; borrowed, must outlive it.
        /// Reads the image a sprite names; optional, borrowed. Without it a sprite draws untextured.
        ke_asset_resolver *resolver;
    } ke_render_scene_resolve_params;

    /// Registers the scene's render components and the update-phase systems
    /// "render.sprite2d.resolve" and "render.mesh.resolve", the second running after the first. A
    /// missing runtime, ecs or service fails as an invalid argument; the handle's ref is NULL on
    /// failure, and the component types registered before it stay registered.
    /// @param out_resolve [out] Receives the handle; left zeroed on failure.
    KE_RENDER_SCENE_API ke_result ke_render_scene_resolve_create(
        const ke_render_scene_resolve_params *params, ke_render_scene_resolve_handle *out_resolve);

#ifdef __cplusplus
}
#endif

#endif

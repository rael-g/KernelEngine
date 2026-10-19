#ifndef KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_CREATE_H_

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
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

    /// The ids the ecs gave the scene's render components, which the passes are created with.
    typedef struct ke_render_scene_component_ids
    {
        ke_component_id mesh;
        ke_component_id camera;
        ke_component_id directional_light;
        ke_component_id point_light;
        ke_component_id spot_light;
        ke_component_id ambient_light;
        ke_component_id skybox;
        ke_component_id sprite2d;
        ke_component_id label;
        ke_component_id world_transform;
    } ke_render_scene_component_ids;

    /// The scene's render components and the update-phase systems that give a mesh and a sprite
    /// the GPU resources they name.
    typedef struct ke_render_scene_resolve
    {
        void *handle;

        /** The ids of the components the scene resolve registered; valid while it lives. */
        const ke_render_scene_component_ids *(*component_ids)(struct ke_render_scene_resolve *self);
    } ke_render_scene_resolve;

    typedef struct ke_render_scene_resolve_handle
    {
        ke_render_scene_resolve *ref;
        void (*destroy)(ke_render_scene_resolve *self);
    } ke_render_scene_resolve_handle;

    /// What the scene resolve needs to register the components and upload what they name.
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
    KE_RENDER_SCENE_API ke_render_scene_resolve_handle ke_render_scene_resolve_create(
        const ke_render_scene_resolve_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif

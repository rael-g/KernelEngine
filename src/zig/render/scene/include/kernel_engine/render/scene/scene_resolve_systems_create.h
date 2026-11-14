#ifndef KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_SYSTEMS_CREATE_H_
#define KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_SYSTEMS_CREATE_H_

#include <kernel_engine/module/module.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/render/scene_resolve.h>

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

#ifdef __cplusplus
extern "C"
{
#endif

    /// Creates the module of @p scene: attaching it registers, in the main world's update set,
    /// "render.sprite2d.resolve" and "render.mesh.resolve", the second after the first, which give a
    /// sprite and a mesh the GPU resources they name.
    /// @param scene [borrowed] Created by this library; must outlive the module.
    /// @param out_module [out] Receives the module; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_OUT_OF_MEMORY.
    KE_RENDER_SCENE_API ke_result ke_render_scene_resolve_systems_create(ke_render_scene_resolve *scene, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif

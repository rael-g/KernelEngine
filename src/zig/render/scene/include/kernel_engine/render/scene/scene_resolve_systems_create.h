#ifndef KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_SYSTEMS_CREATE_H_
#define KERNEL_ENGINE_RENDER_SCENE_SCENE_RESOLVE_SYSTEMS_CREATE_H_

#include <kernel_engine/part/part.h>
#include <kernel_engine/schedule/schedule.h>
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

    /// Registers the systems of @p scene, which give a sprite and a mesh the GPU resources they name:
    /// "render.sprite2d.resolve" in @p update_set of @p update and "render.mesh.resolve" in @p post_update_set of
    /// @p post_update, after it. Every argument but @p out_systems must outlive the systems.
    /// @param scene Created by this library.
    /// @param out_systems [out] Receives the systems, whose destroy unregisters them; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer; KE_RESULT_NOT_SUPPORTED when the systems of
    ///         @p scene are registered; the code of the schedule that refused a system.
    KE_RENDER_SCENE_API ke_result ke_render_scene_resolve_systems_create(
        ke_render_scene_resolve *scene, ke_schedule *update, ke_schedule_set_id update_set, ke_schedule *post_update,
        ke_schedule_set_id post_update_set, ke_owner *out_systems);

#ifdef __cplusplus
}
#endif

#endif

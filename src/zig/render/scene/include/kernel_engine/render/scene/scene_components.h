#ifndef KERNEL_ENGINE_RENDER_SCENE_SCENE_COMPONENTS_H_
#define KERNEL_ENGINE_RENDER_SCENE_SCENE_COMPONENTS_H_

#include <kernel_engine/framework/scene_component_set.h>

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

/**
 * Adds render's scene components to @p set: mesh, camera, the four lights, skybox, sprite and
 * label, with their field tables, and the apply callbacks of the mesh, the camera and the sprite.
 * @param set [borrowed] The set the components are added to.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p set, or the code of the set that refused
 *         a component, after the components added before it.
 */
KE_RENDER_SCENE_API ke_result ke_render_scene_components_create(ke_scene_component_set *set);

#ifdef __cplusplus
}
#endif

#endif

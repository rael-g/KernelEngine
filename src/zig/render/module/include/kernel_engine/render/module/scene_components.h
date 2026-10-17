#ifndef KERNEL_ENGINE_RENDER_MODULE_SCENE_COMPONENTS_H_
#define KERNEL_ENGINE_RENDER_MODULE_SCENE_COMPONENTS_H_

#include <kernel_engine/framework/scene_component_set.h>

#ifndef KE_RENDER_CORE_API
    #if defined(_WIN32) || defined(__CYGWIN__)
        #ifdef KE_RENDER_CORE_EXPORT
            #define KE_RENDER_CORE_API __declspec(dllexport)
        #elif defined(KE_RENDER_CORE_STATIC)
            #define KE_RENDER_CORE_API
        #else
            #define KE_RENDER_CORE_API __declspec(dllimport)
        #endif
    #else
        #define KE_RENDER_CORE_API __attribute__((visibility("default")))
    #endif
#endif

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Returns the set of render's scene components: mesh, camera, the four lights, skybox, sprite and
 * label, with their field tables, and the apply callbacks of the mesh, the camera and the sprite.
 * The set holds no state.
 */
KE_RENDER_CORE_API ke_scene_component_set_handle ke_render_scene_components_create(void);

#ifdef __cplusplus
}
#endif

#endif

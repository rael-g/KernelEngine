#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_CREATE_H_

#include <kernel_engine/framework/scene_loader.h>
#include <kernel_engine/framework/world.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_FRAMEWORK_API
#if defined(_WIN32) || defined(__CYGWIN__)
#ifdef KE_FRAMEWORK_STATIC
#define KE_FRAMEWORK_API
#else
#ifdef KE_FRAMEWORK_EXPORT
#define KE_FRAMEWORK_API __declspec(dllexport)
#else
#define KE_FRAMEWORK_API __declspec(dllimport)
#endif
#endif
#else
#define KE_FRAMEWORK_API __attribute__((visibility("default")))
#endif
#endif

    /// Allocates a scene loader bound to the given world. The loader uses the
    /// world's apply registry to drive [entity.components.X] blocks and the
    /// world's scene_tree to spawn entities. project_root may be NULL — when
    /// provided, "res://" prefixed paths resolve to (project_root + remainder).
    ///
    /// scene_properties lifetime: entries are copied into per-world arenas
    /// owned by the loader; freed at loader.destroy(). After destroy() any
    /// scene_properties component the loader wrote becomes dangling. Destroy
    /// the loader only after the world has shut down OR after removing every
    /// scene_properties component the loader populated.
    KE_FRAMEWORK_API ke_result ke_scene_loader_create(
        struct ke_world   *world,
        const char        *project_root,
        ke_scene_loader  **out_loader);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_CREATE_H_

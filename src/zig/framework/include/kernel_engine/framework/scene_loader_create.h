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
    /// world's component registry to drive [entity.<component>] blocks and the
    /// world's scene_tree to spawn entities. project_root may be NULL — when
    /// provided, "res://" prefixed paths resolve to (project_root + remainder).
    ///
    /// String lifetime: a value a block authors into a char field is copied into
    /// the component, but the parsed entries themselves come from an arena freed
    /// at loader.destroy(). Nothing the loader wrote outlives it by reference.
    KE_FRAMEWORK_API ke_scene_loader_handle ke_scene_loader_create(
        struct ke_world   *world,
        const char        *project_root,
        ke_error         **out_error);

#ifdef __cplusplus
}
#endif

#endif

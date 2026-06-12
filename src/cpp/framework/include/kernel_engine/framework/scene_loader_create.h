#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_CREATE_H_

#include <kernel_engine/kernel/framework/scene_loader.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Allocates a scene loader bound to the given world / tree.
    /// The loader does NOT take ownership of the inputs; the caller keeps them
    /// alive across all load() invocations.
    ///
    /// project_root may be NULL. When provided, nested scene paths starting with
    /// "res://" resolve to (project_root + remainder). When NULL, nested paths
    /// are resolved relative to the loading scene file's directory.
    KE_FRAMEWORK_API ke_result ke_scene_loader_create(
        ke_allocator           *alloc,
        struct ke_world        *world,
        ke_scene_tree          *tree,
        const char             *project_root,
        ke_scene_loader       **out_loader);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_CREATE_H_

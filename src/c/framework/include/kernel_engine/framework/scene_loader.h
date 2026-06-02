#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_

#include <kernel_engine/framework/types.h>
#include <kernel_engine/kernel/common/error.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Scene loader contract ────────────────────────────────────────────────
    //
    // Language-agnostic vtable for loading a scene file into the engine.
    // Each binding (C#, Lua, …) provides its own implementation. A future
    // C plugin (`ke_scene_loader_toml`) will parse TOML and drive the
    // ke_node_type_registry to create and configure nodes without any managed
    // runtime involvement.
    //
    // Until the C impl lands, the C# Framework fills this vtable with
    // [UnmanagedCallersOnly] trampolines that delegate to SceneLoader.LoadAsync.

    typedef struct ke_scene_loader
    {
        void *handle; // opaque; owned by the implementation

        /// Loads the scene file at the UTF-8 path into the world associated
        /// with this loader at construction time. Blocking — does not return
        /// until all nodes are created and all properties applied.
        ke_result (*load)(struct ke_scene_loader *self, const char *path);

        /// Releases resources owned by this loader. After destroy() the
        /// pointer must not be used.
        void (*destroy)(struct ke_scene_loader *self);
    } ke_scene_loader;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_

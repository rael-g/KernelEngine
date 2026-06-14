#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/ecs/ecs.h>     // ke_entity
#include <kernel_engine/kernel/ecs/variant.h>
struct ke_world;

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Scene loader contract ────────────────────────────────────────────────
    //
    // Language-agnostic vtable for loading a `.scene.toml` file into a world.
    // The default plugin (src/c/framework/) uses tomlc99 (vendored) to parse and
    // drives the supplied scene_tree to instantiate ECS entities from a
    // component-driven file:
    //
    //     [[entity]]
    //     name   = "Player"
    //     parent = "World"                   # optional; defaults to root
    //     type   = "Paddle"                  # dispatched to the registered script factory
    //     [entity.transform]
    //     position       = [0, 1, 0]
    //     scale          = [1, 1, 1]
    //     rotation_euler = [0, 90, 0]        # degrees; ZYX order
    //     [entity.components.mesh]
    //     primitive = "cube"
    //     color     = [1, 1, 1, 1]
    //     [entity.properties]                # free-form bag — see ke_scene_properties
    //     MoveAction = "Up"
    //
    // Script language: one factory per game session — the host registers its
    // factory once (C#, Lua, Python, …) and every `type` field in the scene
    // dispatches to that factory. Games use a single scripting language; the
    // loader doesn't need to know which one.

    /// Factory invoked by the loader when an entity has a `type` field. The
    /// host registers exactly one factory (its scripting-language bridge);
    /// the factory's job is to instantiate the wrapper for `type_name` and
    /// bind it to `entity`. Return non-zero to signal a load failure.
    typedef ke_result (*ke_script_factory_func)(
        void *ctx, ke_entity entity, const char *type_name);

    /// ECS component the SceneLoader attaches to every entity that has an
    /// `[entity.properties]` block — the generic key/value bag chosen as
    /// "option C" in §5b of the refactor plan. The component points into
    /// loader-owned storage (the entries + string bytes live in an internal
    /// arena released when ke_scene_loader.destroy() runs), so the loader
    /// must outlive every entity that holds a scene_properties component.
    ///
    /// Bindings consume this the same way they consume any other component:
    /// look up the cid via ke_ecs_component_lookup("scene_properties"), call
    /// ke_ecs_component_get on the entity, walk the entries. A Lua game and a
    /// C# game read the same bytes through the same API; no per-language
    /// callback is involved.
    typedef struct ke_scene_properties
    {
        const ke_variant_table_entry *entries; ///< borrowed; valid until loader.destroy()
        uint32_t                      count;
    } ke_scene_properties;

#define KE_SCENE_PROPERTIES_COMPONENT_NAME "scene_properties"

    typedef struct ke_scene_loader
    {
        void *handle; // opaque; owned by the implementation

        /// Loads the scene file at the UTF-8 path into the world associated
        /// with this loader at construction time. Blocking — does not return
        /// until all nodes are created and all properties applied. Returns
        /// KE_ERROR_NOT_FOUND on a missing/unparseable file.
        ke_result (*load)(struct ke_scene_loader *self, const char *path);

        /// Registers the single script factory for this loader. When the loader
        /// encounters a `type` field on an entity it calls factory(ctx, entity,
        /// type_name). Only one factory is active at a time; calling again
        /// replaces the previous registration. Returns KE_ERROR_INVALID_ARGUMENT
        /// if self or factory is NULL.
        ke_result (*register_script_factory)(struct ke_scene_loader *self,
                                             ke_script_factory_func factory,
                                             void *ctx);

        /// Releases resources owned by this loader. After destroy() the
        /// pointer must not be used, AND any `scene_properties` component the
        /// loader wrote into the world becomes dangling (entries point into
        /// loader-internal storage). Destroy the loader only after the world
        /// has shut down (or after explicitly removing every scene_properties
        /// component you no longer need).
        void (*destroy)(struct ke_scene_loader *self);
    } ke_scene_loader;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_

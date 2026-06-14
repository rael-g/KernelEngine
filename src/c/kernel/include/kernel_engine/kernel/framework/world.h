#ifndef KERNEL_ENGINE_FRAMEWORK_WORLD_H_
#define KERNEL_ENGINE_FRAMEWORK_WORLD_H_

// ke_world — framework-level aggregator: references one ECS storage instance,
// one runtime scheduler, one scene tree, plus per-world conventions
// (project_root for asset_resolver). Multi-world is supported by creating N
// worlds in the same process; each has its own ecs + runtime + scene_tree.
//
// Created by the framework plugin via ke_world_create() (see
// kernel_engine/framework/world_create.h). Other plugins / bindings may
// ship alternative ke_world_create() implementations exporting a different
// vtable shape (e.g. ECS-pure worlds without a scene tree).
//
// Ownership ("quem cria, owna"): world BORROWS ecs + runtime + scene_tree +
// allocator + task_scheduler + logger. The host (or a language wrapper acting
// as host) created those objects and remains responsible for destroying them.
// `world->destroy(world)` frees only the world's own state (apply_registry +
// the state/vtable allocation). Caller must destroy ecs, runtime, scene_tree
// afterwards in reverse-create order.

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/ecs/ecs.h>            // ke_component_id
#include <kernel_engine/kernel/ecs/ke_ecs.h>
#include <kernel_engine/kernel/ecs/variant.h>        // ke_variant_table_entry
#include <kernel_engine/kernel/runtime/runtime.h>

#ifdef __cplusplus
extern "C"
{
#endif

    struct ke_task_scheduler;
    struct ke_scene_tree;
    struct ke_logger;

    /// Per-component "apply" callback — translates a TOML-shaped entry list
    /// (`name=value` pairs) into the raw component memory. Registered by the
    /// framework at world construction for each built-in component (transform,
    /// camera, mesh, lights, scene_properties) and by game code for user
    /// components that want to be declarable in `.scene.toml` files. The
    /// scene_loader queries the world's apply registry when it encounters a
    /// `[entity.components.X]` block — apply lives in the framework, not in
    /// the kernel ECS, because declarative deserialization is a framework
    /// opinion (an ECS-pure alternative framework may not have a scene file
    /// format at all).
    typedef void (*ke_component_apply_fn)(
        void                          *component,
        const ke_variant_table_entry  *entries,
        uint32_t                       count);

    typedef struct ke_world ke_world;

    typedef struct ke_world_params
    {
        ke_allocator             *allocator;       ///< borrowed
        struct ke_task_scheduler *task_scheduler;  ///< borrowed
        ke_ecs                   *ecs;             ///< borrowed; caller destroys after world->destroy()
        ke_runtime               *runtime;         ///< borrowed; caller destroys after world->destroy()
        struct ke_scene_tree     *scene_tree;      ///< borrowed; NULL allowed; caller destroys after world->destroy()
        const char               *project_root;    ///< framework convention (asset_resolver); NULL = res:// disabled
        struct ke_logger         *logger;          ///< borrowed (optional)
    } ke_world_params;

    struct ke_world
    {
        void *handle;  ///< impl-private state

        /// Returns the borrowed ecs pointer the world owns. Valid until destroy().
        ke_ecs *(*ecs)(struct ke_world *self);

        /// Returns the borrowed runtime pointer the world owns. Valid until destroy().
        ke_runtime *(*runtime)(struct ke_world *self);

        /// Returns the borrowed scene_tree pointer the world owns, or NULL if the
        /// world was created without one (C-phase transitional).
        struct ke_scene_tree *(*scene_tree)(struct ke_world *self);

        /// Registers a per-component apply callback. Replaces any previous
        /// registration for the same cid. Returns KE_ERROR_OUT_OF_MEMORY if the
        /// internal registry can't grow. Idempotent at the (cid, fn) level —
        /// calling twice with the same pair is harmless.
        ke_result (*register_component_apply)(struct ke_world      *self,
                                              ke_component_id        cid,
                                              ke_component_apply_fn  apply);

        /// Resolves the apply callback for a cid. Returns NULL if no callback
        /// is registered (the scene_loader skips such components silently,
        /// matching the "unknown component name → skip" semantics).
        ke_component_apply_fn (*get_component_apply)(struct ke_world *self,
                                                     ke_component_id  cid);

        /// Destroys the world's own state (apply_registry + state block). Does NOT
        /// destroy ecs, runtime, or scene_tree — those are borrowed; caller destroys
        /// them in reverse-create order after this call. After this call `self` must
        /// not be used.
        void (*destroy)(struct ke_world *self);
    };

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_WORLD_H_

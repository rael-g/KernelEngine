#ifndef KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_
#define KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_

#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/world/system.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/engine/frame.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Pure ECS runtime: holds the registry, built-in component IDs, and drives systems.
    ///        High-level abstractions (nodes, scenes) belong in the framework layer.
    typedef struct ke_world
    {
        void *handle;
        void (*destroy)(struct ke_world *self);

        /// @brief Returns the ECS registry for direct entity/component manipulation.
        struct ke_ecs_registry *(*get_registry)(struct ke_world *self);

        /// @brief Advances the simulation by one tick.
        ///        Runs the built-in ScriptSystem and TransformSystem, then all registered systems.
        ke_result (*update)(struct ke_world *self, const struct ke_frame *frame);

        /// @brief Registers an external system to be called each frame after the built-in systems.
        ke_result (*add_system)(struct ke_world *self, const ke_system *system);

        // ── Built-in component IDs ─────────────────────────────────────────────
        // These components are registered by ke_world_create and are required
        // by the built-in ScriptSystem and TransformSystem.

        ke_component_id (*transform_id)(struct ke_world *self);
        ke_component_id (*hierarchy_id)(struct ke_world *self);
        ke_component_id (*name_id)(struct ke_world *self);
        ke_component_id (*script_id)(struct ke_world *self);

    } ke_world;

    /// @brief Parameters for world creation.
    typedef struct ke_world_params
    {
        struct ke_allocator *allocator;
    } ke_world_params;

    /// @brief Creates a new ECS world instance.
    KE_API ke_result ke_world_create(const ke_world_params *params, ke_world **out_world);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_

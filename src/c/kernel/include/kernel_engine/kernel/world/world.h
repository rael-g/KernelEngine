#ifndef KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_
#define KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_

#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/world/system.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/engine/frame.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/window/window.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Public interface for the Simulation World.
    /// The world is the single source of truth for scene hierarchy and ECS state.
    /// It owns the ECS registry and drives all built-in systems each frame.
    typedef struct ke_world
    {
        void *handle;
        void (*destroy)(struct ke_world *self);

        /// @brief Returns the ECS registry.
        struct ke_ecs_registry *(*get_registry)(struct ke_world *self);

        /// @brief Advances the simulation by one frame.
        /// Runs ScriptSystem → TransformSystem → user systems.
        ke_result (*update)(struct ke_world *self, const struct ke_frame *frame);

        // ── Node management (replaces ke_scene) ──────────────────────────────

        /// @brief Creates a node entity (TransformComponent + HierarchyComponent +
        ///        NameComponent) and links it to @p parent (root if KE_ENTITY_INVALID).
        ke_entity (*create_node)(struct ke_world *self, const char *name, ke_entity parent);

        /// @brief Destroys a node and all its descendants recursively.
        ke_result (*destroy_node)(struct ke_world *self, ke_entity entity);

        /// @brief Returns the implicit root node entity (always entity 1).
        ke_entity (*get_root)(struct ke_world *self);

        // ── Built-in component IDs ────────────────────────────────────────────

        ke_component_id (*transform_id)(struct ke_world *self);
        ke_component_id (*hierarchy_id)(struct ke_world *self);
        ke_component_id (*name_id)(struct ke_world *self);
        ke_component_id (*script_id)(struct ke_world *self);

        // ── System management ─────────────────────────────────────────────────

        /// @brief Registers a C system to be called each frame by update().
        ke_result (*add_system)(struct ke_world *self, const ke_system *system);

    } ke_world;

    typedef struct ke_world_descriptor
    {
        struct ke_allocator *allocator;
        struct ke_render *renderer;
        struct ke_window *window;
    } ke_world_descriptor;

    /// @brief Creates a new world instance.
    KE_API ke_result ke_world_create(const ke_world_descriptor *desc, ke_world **out_world);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_

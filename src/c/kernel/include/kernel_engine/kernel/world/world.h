#ifndef KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_
#define KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_

#include <kernel_engine/kernel/world/scene.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/engine/frame.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/window/window.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Public interface for the Simulation World.
    /// Container for the Scene Graph, ECS, and core services.
    typedef struct ke_world
    {
        void *handle;
        void (*destroy)(struct ke_world *self);

        struct ke_scene *(*get_scene)(struct ke_world *self);
        struct ke_ecs_registry *(*get_registry)(struct ke_world *self);

        /// @brief Main entry point for the simulation loop.
        /// Processes behaviors, physics, and updates the scene.
        ke_result (*update)(struct ke_world *self, const struct ke_frame *frame);

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

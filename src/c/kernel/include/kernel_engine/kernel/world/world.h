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
    typedef struct ke_world
    {
        void *handle;
        void (*destroy)(struct ke_world *self);

        struct ke_ecs_registry *(*get_registry)(struct ke_world *self);
        ke_result (*update)(struct ke_world *self, const struct ke_frame *frame);

        ke_entity (*create_node)(struct ke_world *self, const char *name, ke_entity parent);
        ke_result (*destroy_node)(struct ke_world *self, ke_entity entity);
        ke_entity (*get_root)(struct ke_world *self);

        ke_component_id (*transform_id)(struct ke_world *self);
        ke_component_id (*hierarchy_id)(struct ke_world *self);
        ke_component_id (*name_id)(struct ke_world *self);
        ke_component_id (*script_id)(struct ke_world *self);
        ke_component_id (*mesh_renderer_id)(struct ke_world *self);

        ke_result (*add_system)(struct ke_world *self, const ke_system *system);

    } ke_world;

    /// @brief Parameters for world creation.
    typedef struct ke_world_params
    {
        struct ke_allocator *allocator;
        struct ke_render *renderer;
        struct ke_window *window;
    } ke_world_params;

    /// @brief Creates a new world instance.
    KE_API ke_result ke_world_create(const ke_world_params *params, ke_world **out_world);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_

#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_COMPONENT_SET_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_COMPONENT_SET_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/framework/world.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// The components a plugin makes addressable from a scene file: each one registered with an
    /// ecs under its name, size and field table, the table handed to a world, and the apply
    /// callback the plugin has for it, if any.
    typedef struct ke_scene_component_set
    {
        void *handle;

        /// Registers every component of the set with @p ecs and @p world. Registrations made
        /// before a failure stay.
        /// @param ecs   [borrowed] The registry the components are registered with.
        /// @param world [borrowed] The world that learns their field tables and apply callbacks.
        /// @return false, with the error set, when an argument is null or the ecs or the world
        ///         refuses a registration.
        bool (*register_into)(struct ke_scene_component_set *self, ke_ecs *ecs, ke_world *world,
                              ke_error **out_error);
    } ke_scene_component_set;

    typedef struct ke_scene_component_set_handle
    {
        ke_scene_component_set *ref;
        void (*destroy)(ke_scene_component_set *self);
    } ke_scene_component_set_handle;

#ifdef __cplusplus
}
#endif

#endif

#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_COMPONENT_SET_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_COMPONENT_SET_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/framework/world.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// The components the plugins make addressable from a scene file. Each plugin adds its own; the
    /// host then registers all of them with an ecs and a world: each component under its name, size
    /// and field table, the table handed to the world, with the apply callback the plugin gave.
    typedef struct ke_scene_component_set
    {
        void *handle;
        /// Adds a component to the set, after those added before it.
        /// @param component [borrowed] Name, size, alignment and field table; copied, while the
        ///                  name and the field table it points at must outlive the set.
        /// @param apply     The callback the world consults after the field table, or NULL.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p component or name, or
        ///         KE_RESULT_OUT_OF_MEMORY.
        ke_result (*add)(struct ke_scene_component_set *self, const ke_component_params *component,
                         ke_component_apply_fn apply);

        /// Registers every component of the set with @p ecs and @p world, in the order they were
        /// added. Registrations made before a failure stay.
        /// @param ecs   [borrowed] The registry the components are registered with.
        /// @param world [borrowed] The world that learns their field tables and apply callbacks.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when an argument is null, or the code of the
        ///         ecs or the world that refused a registration.
        ke_result (*register_into)(struct ke_scene_component_set *self, ke_ecs *ecs, ke_world *world);
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

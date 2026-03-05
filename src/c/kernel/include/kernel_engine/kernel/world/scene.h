#ifndef KERNEL_ENGINE_KERNEL_WORLD_SCENE_H_
#define KERNEL_ENGINE_KERNEL_WORLD_SCENE_H_

#include <kernel_engine/kernel/world/node.h>
#include <kernel_engine/kernel/context/allocator.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Public interface for a Scene.
    /// Manages a hierarchy of nodes and spatial organization.
    typedef struct ke_scene
    {
        void *handle;
        void (*destroy)(struct ke_scene *self);

        struct ke_node *(*get_root)(struct ke_scene *self);
        ke_result (*create_node)(struct ke_scene *self, const ke_node_descriptor *desc, struct ke_node **out_node);
        ke_result (*destroy_node)(struct ke_scene *self, struct ke_node *node);
        
        /// @brief Recalculates all spatial hierarchies.
        void (*update)(struct ke_scene *self);

    } ke_scene;

    typedef struct ke_scene_descriptor
    {
        struct ke_allocator *allocator;
    } ke_scene_descriptor;

    /// @brief Creates a new scene instance.
    KE_API ke_result ke_scene_create(const ke_scene_descriptor *desc, ke_scene **out_scene);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_SCENE_H_

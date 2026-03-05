#ifndef KERNEL_ENGINE_KERNEL_WORLD_NODE_H_
#define KERNEL_ENGINE_KERNEL_WORLD_NODE_H_

#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/types.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint64_t ke_entity;
#define KE_ENTITY_INVALID 0

    typedef struct ke_transform
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
    } ke_transform;

    /// @brief Public interface for a Scene Node.
    /// A node represents a spatial object and a unit of behavior.
    typedef struct ke_node
    {
        void *handle;
        void (*destroy)(struct ke_node *self);

        // Properties
        const char *(*get_name)(struct ke_node *self);
        ke_result (*get_local_transform)(struct ke_node *self, ke_transform *out_transform);
        ke_result (*set_local_transform)(struct ke_node *self, const ke_transform *transform);
        ke_result (*get_world_matrix)(struct ke_node *self, ke_mat4 *out_matrix);

        // Hierarchy
        ke_result (*add_child)(struct ke_node *self, struct ke_node *child);
        ke_result (*remove_child)(struct ke_node *self, struct ke_node *child);
        struct ke_node *(*get_parent)(struct ke_node *self);
        struct ke_node *(*get_first_child)(struct ke_node *self);
        struct ke_node *(*get_next_sibling)(struct ke_node *self);

        // Behavior/Scripting Contract
        ke_result (*on_start)(struct ke_node *self);
        ke_result (*on_update)(struct ke_node *self, float delta_time);

        // Entity Link
        ke_entity (*get_entity)(struct ke_node *self);
        void (*set_entity)(struct ke_node *self, ke_entity entity);

    } ke_node;

    typedef struct ke_node_descriptor
    {
        const char *name;
        struct ke_allocator *allocator;
        // Optional callbacks for custom behavior in C
        ke_result (*on_start)(ke_node *self);
        ke_result (*on_update)(ke_node *self, float dt);
        void *user_data;
    } ke_node_descriptor;

    /// @brief Creates a standard node instance.
    KE_API ke_result ke_node_create(const ke_node_descriptor *desc, ke_node **out_node);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_NODE_H_

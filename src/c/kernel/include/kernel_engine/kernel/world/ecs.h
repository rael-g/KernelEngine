#ifndef KERNEL_ENGINE_KERNEL_WORLD_ECS_H_
#define KERNEL_ENGINE_KERNEL_WORLD_ECS_H_

#include <kernel_engine/kernel/world/node.h> // for ke_entity
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint32_t ke_component_id;

    typedef struct ke_ecs_registry
    {
        struct ke_allocator *allocator;
        ke_entity next_entity;
        // Internal storage structures will go here
        void *internal_data;
    } ke_ecs_registry;

    /// @brief Creates a new ECS registry.
    ke_result ke_ecs_registry_create(struct ke_allocator *alloc, ke_ecs_registry **out_registry);

    /// @brief Destroys an ECS registry.
    void ke_ecs_registry_destroy(ke_ecs_registry *registry);

    /// @brief Creates a new entity.
    ke_entity ke_ecs_entity_create(ke_ecs_registry *registry);

    /// @brief Destroys an entity and all its components.
    void ke_ecs_entity_destroy(ke_ecs_registry *registry, ke_entity entity);

    /// @brief Registers a component type with a given size.
    ke_component_id ke_ecs_component_register(ke_ecs_registry *registry, const char *name, size_t size);

    /// @brief Adds a component to an entity.
    void *ke_ecs_component_add(ke_ecs_registry *registry, ke_entity entity, ke_component_id component);

    /// @brief Removes a component from an entity.
    void ke_ecs_component_remove(ke_ecs_registry *registry, ke_entity entity, ke_component_id component);

    /// @brief Gets a component from an entity.
    void *ke_ecs_component_get(ke_ecs_registry *registry, ke_entity entity, ke_component_id component);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_ECS_H_

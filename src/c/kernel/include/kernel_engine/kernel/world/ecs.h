#ifndef KERNEL_ENGINE_KERNEL_WORLD_ECS_H_
#define KERNEL_ENGINE_KERNEL_WORLD_ECS_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint64_t ke_entity;
#define KE_ENTITY_INVALID 0

    typedef uint32_t ke_component_id;

    typedef struct ke_ecs_registry
    {
        struct ke_allocator *allocator;
        ke_entity next_entity;
        void *internal_data;
    } ke_ecs_registry;

    /// @brief Creates a new ECS registry.
    KE_API ke_result ke_ecs_registry_create(struct ke_allocator *alloc, ke_ecs_registry **out_registry);

    /// @brief Destroys an ECS registry and all component data.
    KE_API void ke_ecs_registry_destroy(ke_ecs_registry *registry);

    /// @brief Creates a new entity and returns its ID.
    KE_API ke_entity ke_ecs_entity_create(ke_ecs_registry *registry);

    /// @brief Destroys an entity and removes all its components.
    KE_API void ke_ecs_entity_destroy(ke_ecs_registry *registry, ke_entity entity);

    /// @brief Registers a component type with a given element size.
    KE_API ke_component_id ke_ecs_component_register(ke_ecs_registry *registry, const char *name, size_t size);

    /// @brief Adds a component to an entity (zeroed). Returns a pointer to it.
    KE_API void *ke_ecs_component_add(ke_ecs_registry *registry, ke_entity entity, ke_component_id component);

    /// @brief Removes a component from an entity.
    KE_API void ke_ecs_component_remove(ke_ecs_registry *registry, ke_entity entity, ke_component_id component);

    /// @brief Returns a pointer to a component, or NULL if not present.
    KE_API void *ke_ecs_component_get(ke_ecs_registry *registry, ke_entity entity, ke_component_id component);

    /// @brief Zero-copy query: returns pointers to the contiguous entity + component arrays.
    /// @param out_entities  Pointer to the entity ID array (valid until next structural change).
    /// @param out_data      Pointer to the contiguous component data array.
    /// @param out_count     Number of entities with this component.
    KE_API void ke_ecs_registry_query(ke_ecs_registry *registry, ke_component_id component,
                               ke_entity **out_entities, void **out_data, size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_ECS_H_

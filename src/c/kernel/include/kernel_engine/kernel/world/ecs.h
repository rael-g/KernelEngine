#ifndef KERNEL_ENGINE_KERNEL_WORLD_ECS_H_
#define KERNEL_ENGINE_KERNEL_WORLD_ECS_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/component_field.h>
#include <kernel_engine/kernel/world/variant.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint64_t ke_entity;
#define KE_ENTITY_INVALID 0

    typedef uint32_t ke_component_id;
#define KE_COMPONENT_INVALID ((ke_component_id)-1)

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
    /// Thin wrapper over ke_ecs_component_register_v2 with no field descriptors —
    /// the type is opaque to the scene loader, accessible only through native code.
    KE_API ke_component_id ke_ecs_component_register(ke_ecs_registry *registry, const char *name, size_t size);

    /// @brief Registers a component type with field metadata. The `fields` array (may be NULL
    /// if `field_count == 0`) is COPIED into registry-owned storage, so the caller's array
    /// can be a stack literal. Each field's `name` string must outlive the registry — pass
    /// string literals, not transient buffers.
    KE_API ke_component_id ke_ecs_component_register_v2(
        ke_ecs_registry           *registry,
        const char                *name,
        size_t                     size,
        const ke_component_field  *fields,
        uint32_t                   field_count);

    /// @brief Result of ke_ecs_component_lookup. Pointers reference registry-owned storage
    /// and stay valid until the registry is destroyed.
    typedef struct ke_component_meta
    {
        ke_component_id            cid;
        size_t                     size;
        const ke_component_field  *fields;
        uint32_t                   field_count;
    } ke_component_meta;

    /// @brief Resolves a component by its registered name. Returns KE_ERROR_NOT_FOUND if no
    /// component with that name is registered. The output struct (when KE_OK) carries the
    /// cid, struct size, and field descriptors.
    KE_API ke_result ke_ecs_component_lookup(
        ke_ecs_registry   *registry,
        const char        *name,
        ke_component_meta *out_meta);

    /// @brief Writes a single property into an entity's component instance by field name.
    /// Looks up the field by name in the component's metadata; if not found, returns
    /// KE_ERROR_NOT_FOUND. Type rules: the variant's type must equal the field's type, with
    /// one exception — a KE_VARIANT_INT may target a KE_VARIANT_FLOAT field (TOML routinely
    /// parses `60` as int when the user wrote `60.0`). String fields store the variant's
    /// pointer verbatim — the caller is responsible for keeping the underlying bytes alive
    /// as long as the component holds the reference.
    ///
    /// Returns KE_ERROR_NOT_FOUND if the component isn't attached to the entity, or if no
    /// field matches the name. Returns KE_ERROR_INVALID_ARGUMENT on type mismatch.
    KE_API ke_result ke_ecs_component_apply_variant(
        ke_ecs_registry  *registry,
        ke_entity         entity,
        ke_component_id   cid,
        const char       *field_name,
        const ke_variant *value);

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

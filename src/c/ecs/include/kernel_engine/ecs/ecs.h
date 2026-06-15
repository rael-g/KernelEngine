#ifndef KERNEL_ENGINE_ECS_ECS_H_
#define KERNEL_ENGINE_ECS_ECS_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/ecs/component_field.h>
#include <kernel_engine/ecs/variant.h>
#include <stdint.h>
#include <stddef.h>

#ifdef KE_ECS_STATIC
#  define KE_ECS_API
#elif defined(KE_ECS_EXPORT)
#  define KE_ECS_API KE_EXPORT
#else
#  define KE_ECS_API KE_IMPORT
#endif

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
        ke_entity            next_entity;
        void                *internal_data;
    } ke_ecs_registry;

    KE_ECS_API ke_result ke_ecs_registry_create(struct ke_allocator *alloc,
                                                 ke_ecs_registry    **out_registry);
    KE_ECS_API void      ke_ecs_registry_destroy(ke_ecs_registry *registry);

    KE_ECS_API ke_entity ke_ecs_entity_create(ke_ecs_registry *registry);
    KE_ECS_API void      ke_ecs_entity_destroy(ke_ecs_registry *registry, ke_entity entity);

    KE_ECS_API ke_component_id ke_ecs_component_register(ke_ecs_registry *registry,
                                                           const char *name,
                                                           size_t size);
    KE_ECS_API ke_component_id ke_ecs_component_register_v2(ke_ecs_registry          *registry,
                                                              const char               *name,
                                                              size_t                    size,
                                                              const ke_component_field *fields,
                                                              uint32_t                  field_count);

    typedef struct ke_component_meta
    {
        ke_component_id           cid;
        size_t                    size;
        const ke_component_field *fields;
        uint32_t                  field_count;
    } ke_component_meta;

    KE_ECS_API ke_result ke_ecs_component_lookup(ke_ecs_registry   *registry,
                                                   const char        *name,
                                                   ke_component_meta *out_meta);

    KE_ECS_API ke_result ke_ecs_component_apply_variant(ke_ecs_registry  *registry,
                                                          ke_entity         entity,
                                                          ke_component_id   cid,
                                                          const char       *field_name,
                                                          const ke_variant *value);

    KE_ECS_API void *ke_ecs_component_add(ke_ecs_registry *registry, ke_entity entity,
                                            ke_component_id component);
    KE_ECS_API void  ke_ecs_component_remove(ke_ecs_registry *registry, ke_entity entity,
                                               ke_component_id component);
    KE_ECS_API void *ke_ecs_component_get(ke_ecs_registry *registry, ke_entity entity,
                                            ke_component_id component);

    KE_ECS_API void ke_ecs_registry_query(ke_ecs_registry *registry, ke_component_id component,
                                            ke_entity **out_entities, void **out_data,
                                            size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_ECS_ECS_H_

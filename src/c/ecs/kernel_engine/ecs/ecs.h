#ifndef KERNEL_ENGINE_ECS_ECS_H_
#define KERNEL_ENGINE_ECS_ECS_H_

#include <kernel_engine/ecs/component_field.h>
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

    typedef struct ke_component_meta
    {
        ke_component_id           cid;
        size_t                    size;
        const ke_component_field *fields;
        uint32_t                  field_count;
    } ke_component_meta;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_ECS_ECS_H_

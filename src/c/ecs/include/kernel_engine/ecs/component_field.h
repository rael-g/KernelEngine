#ifndef KERNEL_ENGINE_ECS_COMPONENT_FIELD_H_
#define KERNEL_ENGINE_ECS_COMPONENT_FIELD_H_

#include <kernel_engine/ecs/variant.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_component_field
    {
        const char     *name;
        ke_variant_type type;
        uint32_t        offset;
        uint32_t        size;
    } ke_component_field;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_ECS_COMPONENT_FIELD_H_

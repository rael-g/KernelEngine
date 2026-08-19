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
        /// What the field holds when nothing authors it. KE_VARIANT_NULL means
        /// the header declared no default and zero stands.
        ke_variant      default_value;
    } ke_component_field;

/** Expands a generated field table into the `fields, field_count` pair. */
#define KE_COMPONENT_FIELDS(table) (table), (uint32_t)(sizeof(table) / sizeof((table)[0]))

#ifdef __cplusplus
}
#endif

#endif

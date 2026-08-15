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
        /// What the field holds when nobody says otherwise, straight from the
        /// header that declares it. KE_VARIANT_NULL means the declaration named
        /// none, and zero stands. Carried here rather than left to each language's
        /// own node constructor, because a component a scene creates has no node:
        /// without this, authoring one field of a block zeroes every other.
        ke_variant      default_value;
    } ke_component_field;

#ifdef __cplusplus
}
#endif

#endif

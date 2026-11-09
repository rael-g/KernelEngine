#ifndef KERNEL_ENGINE_ECS_COMPONENT_FIELD_H_
#define KERNEL_ENGINE_ECS_COMPONENT_FIELD_H_

#include <kernel_engine/ecs/variant.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [borrowed] One field of a component: where it lies, what a scene writes into it, and the
    /// names an integer field may be written as.
    typedef struct ke_component_field
    {
        const char     *name; ///< [utf8] The name a scene writes the field by.
        ke_variant_type type;
        uint32_t        offset;
        uint32_t        size;
        /// What the field holds when nothing authors it. KE_VARIANT_NULL means
        /// the header declared no default and zero stands.
        ke_variant      default_value;
        /// [utf8, array_of:enum_count, default:empty] The names a scene may write for an integer
        /// field, in value order; a name stands for its index. None leaves the field numeric.
        const char *const *enum_names;
        uint32_t           enum_count; ///< Entries in `enum_names`.
    } ke_component_field;

/** Expands a field table into the `fields` and `field_count` initializers of ke_component_params. */
#define KE_COMPONENT_FIELDS(table) .fields = (table), .field_count = (uint32_t)(sizeof(table) / sizeof((table)[0]))

#ifdef __cplusplus
}
#endif

#endif

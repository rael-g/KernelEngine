#ifndef KERNEL_ENGINE_ECS_ECS_H_
#define KERNEL_ENGINE_ECS_ECS_H_

#include <kernel_engine/ecs/component_field.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [id]
    typedef uint64_t ke_entity;
#define KE_ENTITY_INVALID 0

    /// [id]
    typedef uint32_t ke_component_id;
#define KE_COMPONENT_INVALID 0

    /// [bag] What a component type is registered with.
    typedef struct ke_component_params
    {
        const char               *name;        ///< [borrowed,utf8] Unique component name.
        size_t                    size;        ///< Bytes per entity; 0 registers a tag (no storage).
        size_t                    alignment;   ///< A power of two for a sized component; ignored for a tag of size 0.
        const ke_component_field *fields;      ///< [borrowed,optional,array_of:field_count] The type's field layout, normally its field table; copied with every name it reaches, so it only has to live for the call. NULL registers the size alone.
        uint32_t                  field_count; ///< Entries in `fields`; 0 when `fields` is NULL.
    } ke_component_params;

    typedef struct ke_component_meta
    {
        ke_component_id           cid;
        size_t                    size;
        size_t                    alignment;
        const ke_component_field *fields; ///< [array_of:field_count]
        uint32_t                  field_count;
    } ke_component_meta;

#ifdef __cplusplus
}
#endif

#endif

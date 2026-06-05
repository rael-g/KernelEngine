#ifndef KERNEL_ENGINE_KERNEL_WORLD_COMPONENT_FIELD_H_
#define KERNEL_ENGINE_KERNEL_WORLD_COMPONENT_FIELD_H_

// ke_component_field — per-component-type field descriptor.
//
// Bindings (SceneLoader, editor, debug inspector) use these descriptors to
// write into component memory by field name without owning a custom
// callback per component type. The framework's scene loader, for example,
// iterates `[entity.components.<name>]` TOML tables, looks the component up
// by name (`ke_ecs_component_lookup`), and writes each property via
// `ke_ecs_component_apply_variant`. No per-binding decoding code runs.
//
// Field types reuse the ke_variant_type enum so the variant carrying the
// property and the field describing the destination share a single
// vocabulary. The decoder enforces a type match (with one allowance: a
// KE_VARIANT_INT may target a KE_VARIANT_FLOAT field — TOML often parses
// `60` as int when the user meant `60.0`).

#include <kernel_engine/kernel/world/variant.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_component_field
    {
        const char     *name;   ///< Property key in the TOML scene file.
        ke_variant_type type;   ///< Expected variant kind; must match (modulo INT→FLOAT).
        uint32_t        offset; ///< Byte offset into the component struct.
    } ke_component_field;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_COMPONENT_FIELD_H_

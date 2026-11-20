#ifndef KERNEL_ENGINE_SPATIAL_COMPONENT_FIELDS_H_
#define KERNEL_ENGINE_SPATIAL_COMPONENT_FIELDS_H_

#include <kernel_engine/ecs/component_field.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/spatial/transform.h>
#include <stdalign.h>
#include <stddef.h>
#include <stdint.h>

/// The fields of `ke_transform_component` a scene or the game writes by name: each name, kind, place, size, default
/// and, for an enumeration, its value names.
static const ke_component_field ke_transform_component_fields[] = {
    { "position", KE_VARIANT_VEC3, offsetof(ke_transform_component, position), sizeof(((ke_transform_component *)0)->position), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "rotation", KE_VARIANT_QUAT, offsetof(ke_transform_component, rotation), sizeof(((ke_transform_component *)0)->rotation), { KE_VARIANT_QUAT, { .q = { 0.0f, 0.0f, 0.0f, 1.0f } } }, NULL, 0 },
    { "scale", KE_VARIANT_VEC3, offsetof(ke_transform_component, scale), sizeof(((ke_transform_component *)0)->scale), { KE_VARIANT_VEC3, { .v3 = { 1.0f, 1.0f, 1.0f } } }, NULL, 0 },
};

/// The fields of `ke_transform2d_component` a scene or the game writes by name: each name, kind, place, size, default
/// and, for an enumeration, its value names.
static const ke_component_field ke_transform2d_component_fields[] = {
    { "position", KE_VARIANT_VEC2, offsetof(ke_transform2d_component, position), sizeof(((ke_transform2d_component *)0)->position), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "rotation", KE_VARIANT_FLOAT, offsetof(ke_transform2d_component, rotation), sizeof(((ke_transform2d_component *)0)->rotation), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "scale", KE_VARIANT_VEC2, offsetof(ke_transform2d_component, scale), sizeof(((ke_transform2d_component *)0)->scale), { KE_VARIANT_VEC2, { .v2 = { 1.0f, 1.0f } } }, NULL, 0 },
    { "depth", KE_VARIANT_FLOAT, offsetof(ke_transform2d_component, depth), sizeof(((ke_transform2d_component *)0)->depth), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
};

/// How `ke_transform_component` is registered: its name, size, alignment and field table.
static const ke_component_desc ke_transform_component_desc = { KE_COMPONENT_NAME_TRANSFORM, sizeof(ke_transform_component), alignof(ke_transform_component), ke_transform_component_fields, (uint32_t)(sizeof ke_transform_component_fields / sizeof ke_transform_component_fields[0]) };

/// How `ke_transform2d_component` is registered: its name, size, alignment and field table.
static const ke_component_desc ke_transform2d_component_desc = { KE_COMPONENT_NAME_TRANSFORM2D, sizeof(ke_transform2d_component), alignof(ke_transform2d_component), ke_transform2d_component_fields, (uint32_t)(sizeof ke_transform2d_component_fields / sizeof ke_transform2d_component_fields[0]) };

/// How `ke_world_transform_component` is registered: its name, size, alignment, and no field table.
static const ke_component_desc ke_world_transform_component_desc = { KE_COMPONENT_NAME_WORLD_TRANSFORM, sizeof(ke_world_transform_component), alignof(ke_world_transform_component), NULL, 0 };

#endif

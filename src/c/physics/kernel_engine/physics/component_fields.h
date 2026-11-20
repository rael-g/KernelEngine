#ifndef KERNEL_ENGINE_PHYSICS_COMPONENT_FIELDS_H_
#define KERNEL_ENGINE_PHYSICS_COMPONENT_FIELDS_H_

#include <kernel_engine/ecs/component_field.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/physics/components.h>
#include <stdalign.h>
#include <stddef.h>
#include <stdint.h>

/// The fields of `ke_body2d_component` a scene or the game writes by name: each name, kind, place, size, default
/// and, for an enumeration, its value names.
static const ke_component_field ke_body2d_component_fields[] = {
    { "type", KE_VARIANT_INT, offsetof(ke_body2d_component, type), sizeof(((ke_body2d_component *)0)->type), { KE_VARIANT_NULL, { 0 } }, (const char *const[]){ "static", "kinematic", "dynamic" }, 3 },
    { "velocity", KE_VARIANT_VEC2, offsetof(ke_body2d_component, velocity), sizeof(((ke_body2d_component *)0)->velocity), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "impulse", KE_VARIANT_VEC2, offsetof(ke_body2d_component, impulse), sizeof(((ke_body2d_component *)0)->impulse), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "angular_velocity", KE_VARIANT_FLOAT, offsetof(ke_body2d_component, angular_velocity), sizeof(((ke_body2d_component *)0)->angular_velocity), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "gravity_scale", KE_VARIANT_FLOAT, offsetof(ke_body2d_component, gravity_scale), sizeof(((ke_body2d_component *)0)->gravity_scale), { KE_VARIANT_FLOAT, { .f = 1.0 } }, NULL, 0 },
    { "fixed_rotation", KE_VARIANT_BOOL, offsetof(ke_body2d_component, fixed_rotation), sizeof(((ke_body2d_component *)0)->fixed_rotation), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
};

/// The fields of `ke_collider2d_component` a scene or the game writes by name: each name, kind, place, size, default
/// and, for an enumeration, its value names.
static const ke_component_field ke_collider2d_component_fields[] = {
    { "kind", KE_VARIANT_INT, offsetof(ke_collider2d_component, kind), sizeof(((ke_collider2d_component *)0)->kind), { KE_VARIANT_NULL, { 0 } }, (const char *const[]){ "box", "circle" }, 2 },
    { "half_extents", KE_VARIANT_VEC2, offsetof(ke_collider2d_component, half_extents), sizeof(((ke_collider2d_component *)0)->half_extents), { KE_VARIANT_VEC2, { .v2 = { 0.5f, 0.5f } } }, NULL, 0 },
    { "radius", KE_VARIANT_FLOAT, offsetof(ke_collider2d_component, radius), sizeof(((ke_collider2d_component *)0)->radius), { KE_VARIANT_FLOAT, { .f = 0.5 } }, NULL, 0 },
    { "density", KE_VARIANT_FLOAT, offsetof(ke_collider2d_component, density), sizeof(((ke_collider2d_component *)0)->density), { KE_VARIANT_FLOAT, { .f = 1.0 } }, NULL, 0 },
    { "friction", KE_VARIANT_FLOAT, offsetof(ke_collider2d_component, friction), sizeof(((ke_collider2d_component *)0)->friction), { KE_VARIANT_FLOAT, { .f = 0.3 } }, NULL, 0 },
    { "restitution", KE_VARIANT_FLOAT, offsetof(ke_collider2d_component, restitution), sizeof(((ke_collider2d_component *)0)->restitution), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "layer", KE_VARIANT_INT, offsetof(ke_collider2d_component, layer), sizeof(((ke_collider2d_component *)0)->layer), { KE_VARIANT_INT, { .i = 1 } }, NULL, 0 },
    { "mask", KE_VARIANT_INT, offsetof(ke_collider2d_component, mask), sizeof(((ke_collider2d_component *)0)->mask), { KE_VARIANT_INT, { .i = 4294967295 } }, NULL, 0 },
    { "attached", KE_VARIANT_BOOL, offsetof(ke_collider2d_component, attached), sizeof(((ke_collider2d_component *)0)->attached), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
};

/// How `ke_body2d_component` is registered: its name, size, alignment and field table.
static const ke_component_desc ke_body2d_component_desc = { KE_COMPONENT_NAME_BODY2D, sizeof(ke_body2d_component), alignof(ke_body2d_component), ke_body2d_component_fields, (uint32_t)(sizeof ke_body2d_component_fields / sizeof ke_body2d_component_fields[0]) };

/// How `ke_collider2d_component` is registered: its name, size, alignment and field table.
static const ke_component_desc ke_collider2d_component_desc = { KE_COMPONENT_NAME_COLLIDER2D, sizeof(ke_collider2d_component), alignof(ke_collider2d_component), ke_collider2d_component_fields, (uint32_t)(sizeof ke_collider2d_component_fields / sizeof ke_collider2d_component_fields[0]) };

#endif

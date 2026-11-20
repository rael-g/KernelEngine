#ifndef KERNEL_ENGINE_RENDER_UI_COMPONENT_FIELDS_H_
#define KERNEL_ENGINE_RENDER_UI_COMPONENT_FIELDS_H_

#include <kernel_engine/ecs/component_field.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/ui/components.h>
#include <stdalign.h>
#include <stddef.h>
#include <stdint.h>

/// The fields of `ke_ui_quad_component` a scene or the game writes by name: each name, kind, place, size, default
/// and, for an enumeration, its value names.
static const ke_component_field ke_ui_quad_component_fields[] = {
    { "texture_bits", KE_VARIANT_INT, offsetof(ke_ui_quad_component, texture_bits), sizeof(((ke_ui_quad_component *)0)->texture_bits), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "dst_x", KE_VARIANT_FLOAT, offsetof(ke_ui_quad_component, dst_x), sizeof(((ke_ui_quad_component *)0)->dst_x), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "dst_y", KE_VARIANT_FLOAT, offsetof(ke_ui_quad_component, dst_y), sizeof(((ke_ui_quad_component *)0)->dst_y), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "dst_w", KE_VARIANT_FLOAT, offsetof(ke_ui_quad_component, dst_w), sizeof(((ke_ui_quad_component *)0)->dst_w), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "dst_h", KE_VARIANT_FLOAT, offsetof(ke_ui_quad_component, dst_h), sizeof(((ke_ui_quad_component *)0)->dst_h), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "u0", KE_VARIANT_FLOAT, offsetof(ke_ui_quad_component, u0), sizeof(((ke_ui_quad_component *)0)->u0), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "v0", KE_VARIANT_FLOAT, offsetof(ke_ui_quad_component, v0), sizeof(((ke_ui_quad_component *)0)->v0), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "u1", KE_VARIANT_FLOAT, offsetof(ke_ui_quad_component, u1), sizeof(((ke_ui_quad_component *)0)->u1), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "v1", KE_VARIANT_FLOAT, offsetof(ke_ui_quad_component, v1), sizeof(((ke_ui_quad_component *)0)->v1), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "color", KE_VARIANT_VEC4, offsetof(ke_ui_quad_component, color), sizeof(((ke_ui_quad_component *)0)->color), { KE_VARIANT_VEC4, { .v4 = { 1.0f, 1.0f, 1.0f, 1.0f } } }, NULL, 0 },
};

/// The fields of `ke_label_component` a scene or the game writes by name: each name, kind, place, size, default
/// and, for an enumeration, its value names.
static const ke_component_field ke_label_component_fields[] = {
    { "font", KE_VARIANT_STRING, offsetof(ke_label_component, font), sizeof(((ke_label_component *)0)->font), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "font_size", KE_VARIANT_FLOAT, offsetof(ke_label_component, font_size), sizeof(((ke_label_component *)0)->font_size), { KE_VARIANT_FLOAT, { .f = 32.0 } }, NULL, 0 },
    { "anchor", KE_VARIANT_VEC2, offsetof(ke_label_component, anchor), sizeof(((ke_label_component *)0)->anchor), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "offset", KE_VARIANT_VEC2, offsetof(ke_label_component, offset), sizeof(((ke_label_component *)0)->offset), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "color", KE_VARIANT_VEC4, offsetof(ke_label_component, color), sizeof(((ke_label_component *)0)->color), { KE_VARIANT_VEC4, { .v4 = { 1.0f, 1.0f, 1.0f, 1.0f } } }, NULL, 0 },
    { "text", KE_VARIANT_STRING, offsetof(ke_label_component, text), sizeof(((ke_label_component *)0)->text), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
};

/// How `ke_ui_quad_component` is registered: its name, size, alignment and field table.
static const ke_component_desc ke_ui_quad_component_desc = { KE_COMPONENT_NAME_UI_QUAD, sizeof(ke_ui_quad_component), alignof(ke_ui_quad_component), ke_ui_quad_component_fields, (uint32_t)(sizeof ke_ui_quad_component_fields / sizeof ke_ui_quad_component_fields[0]) };

/// How `ke_label_component` is registered: its name, size, alignment and field table.
static const ke_component_desc ke_label_component_desc = { KE_COMPONENT_NAME_LABEL, sizeof(ke_label_component), alignof(ke_label_component), ke_label_component_fields, (uint32_t)(sizeof ke_label_component_fields / sizeof ke_label_component_fields[0]) };

#endif

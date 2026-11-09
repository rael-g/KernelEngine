#ifndef KERNEL_ENGINE_SDK_FIELD_H_
#define KERNEL_ENGINE_SDK_FIELD_H_

#include <kernel_engine/ecs/component_field.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/math/math.h>

#include <stddef.h>
#include <stdint.h>

/**
 * @file
 * Entries of a component's field table derived from the struct itself: the member's name, offset,
 * size and variant type, with no default, so a scene writes the member by name; and the
 * description of a component from its struct type.
 */

/**
 * The variant type of an expression: bool, a 32-bit integer, float, a char array (a string),
 * ke_vec2, ke_vec3, ke_vec4, ke_quat or ke_action_ref (written as the action's name). Any other
 * type does not compile.
 */
#define KE_FIELD_TYPE(expr) _Generic((expr), \
    bool: KE_VARIANT_BOOL,                   \
    int32_t: KE_VARIANT_INT,                 \
    uint32_t: KE_VARIANT_INT,                \
    float: KE_VARIANT_FLOAT,                 \
    char *: KE_VARIANT_STRING,               \
    ke_vec2: KE_VARIANT_VEC2,                \
    ke_vec3: KE_VARIANT_VEC3,                \
    ke_vec4: KE_VARIANT_VEC4,                \
    ke_quat: KE_VARIANT_QUAT,                \
    ke_action_ref: KE_VARIANT_STRING)

/** The bytes a scene may write into an expression: the name of an action reference, else all of it. */
#define KE_FIELD_SIZE(expr) _Generic((expr), ke_action_ref: KE_ACTION_NAME_MAX, default: sizeof(expr))

/** The ke_component_field entry of @p member of the struct type @p type. */
#define KE_FIELD(type, member)                                          \
    { #member, KE_FIELD_TYPE(((type *)0)->member), (uint32_t)offsetof(type, member), \
      (uint32_t)KE_FIELD_SIZE(((type *)0)->member), { KE_VARIANT_NULL, { 0 } }, NULL, 0 }

/** The ke_component_params of the struct type @p type registered as @p component_name with the field table @p fields. */
#define KE_COMPONENT(type, component_name, fields) \
    { .name = (component_name), .size = sizeof(type), .alignment = _Alignof(type), KE_COMPONENT_FIELDS(fields) }

/** The ke_component_params of the struct type @p type registered as @p component_name with no field table. */
#define KE_COMPONENT_UNTABLED(type, component_name) \
    { .name = (component_name), .size = sizeof(type), .alignment = _Alignof(type) }

#endif

#ifndef KERNEL_ENGINE_ECS_VARIANT_H_
#define KERNEL_ENGINE_ECS_VARIANT_H_

#include <kernel_engine/math/math.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef enum ke_variant_type
    {
        KE_VARIANT_NULL   = 0,
        KE_VARIANT_BOOL   = 1,
        KE_VARIANT_INT    = 2,
        KE_VARIANT_FLOAT  = 3,
        KE_VARIANT_STRING = 4,
        KE_VARIANT_VEC2   = 5,
        KE_VARIANT_VEC3   = 6,
        KE_VARIANT_VEC4   = 7,
        KE_VARIANT_QUAT   = 8,
        KE_VARIANT_TABLE  = 9,
    } ke_variant_type;

    struct ke_variant_table;

    typedef struct ke_variant
    {
        ke_variant_type type;
        union
        {
            bool       b;
            int64_t    i;
            double     f;
            const char *s;
            ke_vec2    v2;
            ke_vec3    v3;
            ke_vec4    v4;
            ke_quat    q;
            const struct ke_variant_table *t;
        };
    } ke_variant;

    /// One authored key and its value. Whoever accepts the key sets `consumed`;
    /// the loader reports every entry left unclaimed.
    typedef struct ke_variant_table_entry
    {
        const char *key;
        ke_variant  value;
        bool        consumed;
    } ke_variant_table_entry;

    typedef struct ke_variant_table
    {
        uint32_t                      count;
        const ke_variant_table_entry *entries;
    } ke_variant_table;

#ifdef __cplusplus
}
#endif

#endif

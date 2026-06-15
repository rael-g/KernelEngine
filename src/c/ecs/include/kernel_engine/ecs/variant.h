#ifndef KERNEL_ENGINE_ECS_VARIANT_H_
#define KERNEL_ENGINE_ECS_VARIANT_H_

#include <kernel_engine/common/math.h>
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

    typedef struct ke_variant_table_entry
    {
        const char *key;
        ke_variant  value;
    } ke_variant_table_entry;

    typedef struct ke_variant_table
    {
        uint32_t                      count;
        const ke_variant_table_entry *entries;
    } ke_variant_table;

    static inline ke_variant ke_variant_null(void)
        { ke_variant v; v.type = KE_VARIANT_NULL; v.i = 0; return v; }
    static inline ke_variant ke_variant_bool(bool b)
        { ke_variant v; v.type = KE_VARIANT_BOOL; v.b = b; return v; }
    static inline ke_variant ke_variant_int(int64_t i)
        { ke_variant v; v.type = KE_VARIANT_INT; v.i = i; return v; }
    static inline ke_variant ke_variant_float(double f)
        { ke_variant v; v.type = KE_VARIANT_FLOAT; v.f = f; return v; }
    static inline ke_variant ke_variant_string(const char *s)
        { ke_variant v; v.type = KE_VARIANT_STRING; v.s = s; return v; }
    static inline ke_variant ke_variant_vec2(float x, float y)
        { ke_variant v; v.type = KE_VARIANT_VEC2; v.v2.x = x; v.v2.y = y; return v; }
    static inline ke_variant ke_variant_vec3(float x, float y, float z)
        { ke_variant v; v.type = KE_VARIANT_VEC3; v.v3.x = x; v.v3.y = y; v.v3.z = z; return v; }
    static inline ke_variant ke_variant_vec4(float x, float y, float z, float w)
        { ke_variant v; v.type = KE_VARIANT_VEC4; v.v4.x = x; v.v4.y = y; v.v4.z = z; v.v4.w = w; return v; }
    static inline ke_variant ke_variant_quat(float x, float y, float z, float w)
        { ke_variant v; v.type = KE_VARIANT_QUAT; v.q.x = x; v.q.y = y; v.q.z = z; v.q.w = w; return v; }
    static inline ke_variant ke_variant_table_v(const ke_variant_table *t)
        { ke_variant v; v.type = KE_VARIANT_TABLE; v.t = t; return v; }

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_ECS_VARIANT_H_

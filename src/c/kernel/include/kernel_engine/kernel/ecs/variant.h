#ifndef KERNEL_ENGINE_KERNEL_WORLD_VARIANT_H_
#define KERNEL_ENGINE_KERNEL_WORLD_VARIANT_H_

#include <kernel_engine/kernel/common/math.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Variant type tag ─────────────────────────────────────────────────────

    typedef enum ke_variant_type
    {
        KE_VARIANT_NULL   = 0,
        KE_VARIANT_BOOL   = 1,
        KE_VARIANT_INT    = 2,  // int64_t
        KE_VARIANT_FLOAT  = 3,  // double
        KE_VARIANT_STRING = 4,  // null-terminated UTF-8; caller owns lifetime
        KE_VARIANT_VEC2   = 5,
        KE_VARIANT_VEC3   = 6,
        KE_VARIANT_VEC4   = 7,
        KE_VARIANT_QUAT   = 8,
        KE_VARIANT_TABLE  = 9,  // nested key→variant map (inline TOML tables, etc.)
    } ke_variant_type;

    // Forward decl — defined below.
    struct ke_variant_table;

    // ── Variant value ────────────────────────────────────────────────────────
    //
    // Passed by value across the kernel ABI — keep it blittable (no pointers
    // into managed heaps). KE_VARIANT_STRING carries a pointer that is valid
    // for the duration of the set_property call only; implementors must copy
    // if they need to retain the string.

    typedef struct ke_variant
    {
        ke_variant_type type;
        union
        {
            bool      b;
            int64_t   i;
            double    f;
            const char *s;
            ke_vec2   v2;
            ke_vec3   v3;
            ke_vec4   v4;
            ke_quat   q;
            const struct ke_variant_table *t; // KE_VARIANT_TABLE — borrowed, valid for the callback only
        };
    } ke_variant;

    // ── Table variant ────────────────────────────────────────────────────────
    //
    // Carries an inline TOML table (or any key→value bag) across the ABI. Like
    // KE_VARIANT_STRING, entries are borrowed — valid only for the duration of
    // the set_property call. Recursion is supported (a value can be another
    // KE_VARIANT_TABLE).

    typedef struct ke_variant_table_entry
    {
        const char *key;   // null-terminated UTF-8, borrowed
        ke_variant  value; // recursive
    } ke_variant_table_entry;

    typedef struct ke_variant_table
    {
        uint32_t                       count;
        const ke_variant_table_entry  *entries;
    } ke_variant_table;

    // ── Convenience constructors (inline, zero overhead) ─────────────────────

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

#endif // KERNEL_ENGINE_KERNEL_WORLD_VARIANT_H_

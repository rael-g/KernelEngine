#ifndef KERNEL_ENGINE_ECS_COMPONENT_FIELD_WRITE_H_
#define KERNEL_ENGINE_ECS_COMPONENT_FIELD_WRITE_H_

#include <kernel_engine/ecs/component_field.h>
#include <string.h>

#ifdef __cplusplus
extern "C"
{
#endif

    static inline bool ke_variant_as_float(const ke_variant *v, float *out)
    {
        switch (v->type)
        {
        case KE_VARIANT_FLOAT: *out = (float)v->f; return true;
        case KE_VARIANT_INT: *out = (float)v->i; return true;
        default: return false;
        }
    }

    static inline bool ke_variant_as_int(const ke_variant *v, int64_t *out)
    {
        switch (v->type)
        {
        case KE_VARIANT_INT: *out = v->i; return true;
        case KE_VARIANT_FLOAT: *out = (int64_t)v->f; return true;
        case KE_VARIANT_BOOL: *out = v->b ? 1 : 0; return true;
        default: return false;
        }
    }

    static inline bool ke_variant_as_bool(const ke_variant *v, int64_t *out)
    {
        switch (v->type)
        {
        case KE_VARIANT_BOOL: *out = v->b ? 1 : 0; return true;
        case KE_VARIANT_INT: *out = v->i != 0 ? 1 : 0; return true;
        default: return false;
        }
    }

    /** A vec4 out of anything narrower, filling w with 1. */
    static inline bool ke_variant_as_vec4(const ke_variant *v, ke_vec4 *out)
    {
        switch (v->type)
        {
        case KE_VARIANT_VEC4: *out = v->v4; return true;
        case KE_VARIANT_QUAT: out->x = v->q.x; out->y = v->q.y; out->z = v->q.z; out->w = v->q.w; return true;
        case KE_VARIANT_VEC3: out->x = v->v3.x; out->y = v->v3.y; out->z = v->v3.z; out->w = 1.0f; return true;
        default: return false;
        }
    }

    /** A vec3 out of anything narrower, filling z with 0. */
    static inline bool ke_variant_as_vec3(const ke_variant *v, ke_vec3 *out)
    {
        switch (v->type)
        {
        case KE_VARIANT_VEC3: *out = v->v3; return true;
        case KE_VARIANT_VEC4: out->x = v->v4.x; out->y = v->v4.y; out->z = v->v4.z; return true;
        case KE_VARIANT_VEC2: out->x = v->v2.x; out->y = v->v2.y; out->z = 0.0f; return true;
        default: return false;
        }
    }

    static inline bool ke_variant_as_vec2(const ke_variant *v, ke_vec2 *out)
    {
        switch (v->type)
        {
        case KE_VARIANT_VEC2: *out = v->v2; return true;
        case KE_VARIANT_VEC3: out->x = v->v3.x; out->y = v->v3.y; return true;
        case KE_VARIANT_VEC4: out->x = v->v4.x; out->y = v->v4.y; return true;
        default: return false;
        }
    }

    static inline void ke_component_field_write_bytes(unsigned char *base, const ke_component_field *field,
                                                      const void *src, uint32_t size)
    {
        if (size != field->size) { return; }
        memcpy(base + field->offset, src, size);
    }

    static inline void ke_component_field_write_int(unsigned char *base, const ke_component_field *field, int64_t value)
    {
        switch (field->size)
        {
        case 1: { uint8_t  n = (uint8_t)value;  memcpy(base + field->offset, &n, 1); break; }
        case 2: { uint16_t n = (uint16_t)value; memcpy(base + field->offset, &n, 2); break; }
        case 4: { uint32_t n = (uint32_t)value; memcpy(base + field->offset, &n, 4); break; }
        case 8: { uint64_t n = (uint64_t)value; memcpy(base + field->offset, &n, 8); break; }
        default: break;
        }
    }

    /**
     * Writes one variant into the field it describes, converting where the two
     * agree and leaving the field untouched where they do not.
     * @param component [borrowed] Base address of the component's storage.
     * @param field [borrowed] The field to write.
     * @param value [borrowed] The value to write.
     */
    static inline void ke_component_field_write(void *component, const ke_component_field *field,
                                                const ke_variant *value)
    {
        if (component == NULL || field == NULL || value == NULL) { return; }
        unsigned char *base = (unsigned char *)component;

        switch (field->type)
        {
        case KE_VARIANT_FLOAT:
        {
            float f;
            if (!ke_variant_as_float(value, &f)) { return; }
            if (field->size == 4) { ke_component_field_write_bytes(base, field, &f, 4); }
            else if (field->size == 8) { double d = (double)f; ke_component_field_write_bytes(base, field, &d, 8); }
            return;
        }
        case KE_VARIANT_INT:
        {
            int64_t i;
            if (!ke_variant_as_int(value, &i)) { return; }
            ke_component_field_write_int(base, field, i);
            return;
        }
        case KE_VARIANT_BOOL:
        {
            int64_t b;
            if (!ke_variant_as_bool(value, &b)) { return; }
            ke_component_field_write_int(base, field, b);
            return;
        }
        case KE_VARIANT_VEC2:
        {
            ke_vec2 val;
            if (!ke_variant_as_vec2(value, &val)) { return; }
            ke_component_field_write_bytes(base, field, &val, (uint32_t)sizeof(val));
            return;
        }
        case KE_VARIANT_VEC3:
        {
            ke_vec3 val;
            if (!ke_variant_as_vec3(value, &val)) { return; }
            ke_component_field_write_bytes(base, field, &val, (uint32_t)sizeof(val));
            return;
        }
        case KE_VARIANT_VEC4:
        case KE_VARIANT_QUAT:
        {
            ke_vec4 val;
            if (!ke_variant_as_vec4(value, &val)) { return; }
            ke_component_field_write_bytes(base, field, &val, (uint32_t)sizeof(val));
            return;
        }
        case KE_VARIANT_STRING:
        {
            if (value->type != KE_VARIANT_STRING || value->s == NULL || field->size == 0) { return; }
            size_t src_len = strlen(value->s);
            size_t n       = src_len < (size_t)field->size - 1 ? src_len : (size_t)field->size - 1;
            memcpy(base + field->offset, value->s, n);
            base[field->offset + n] = 0;
            return;
        }
        default: return;
        }
    }

    /**
     * Writes every default the field table declares into a component, leaving
     * fields whose default is KE_VARIANT_NULL as they are.
     * @param component [borrowed] Base address of the component's storage.
     * @param fields [borrowed,optional] The type's field table.
     * @param field_count Entries in `fields`.
     */
    static inline void ke_component_fields_seed_defaults(void *component, const ke_component_field *fields,
                                                         uint32_t field_count)
    {
        if (component == NULL || fields == NULL) { return; }
        for (uint32_t i = 0; i < field_count; ++i)
        {
            if (fields[i].default_value.type == KE_VARIANT_NULL) { continue; }
            ke_component_field_write(component, &fields[i], &fields[i].default_value);
        }
    }

#ifdef __cplusplus
}
#endif

#endif

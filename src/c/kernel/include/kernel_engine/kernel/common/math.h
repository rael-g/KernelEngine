#ifndef KERNEL_ENGINE_KERNEL_COMMON_MATH_H_
#define KERNEL_ENGINE_KERNEL_COMMON_MATH_H_

#include <string.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_vec3
    {
        float x, y, z;
    } ke_vec3;

    typedef struct ke_vec4
    {
        float x, y, z, w;
    } ke_vec4;

    typedef struct ke_quat
    {
        float x, y, z, w;
    } ke_quat;

    typedef struct ke_mat4
    {
        float m[16];
    } ke_mat4;

    static inline void ke_mat4_identity(ke_mat4 *out)
    {
        memset(out->m, 0, sizeof(float) * 16);
        out->m[0] = 1.0f;
        out->m[5] = 1.0f;
        out->m[10] = 1.0f;
        out->m[15] = 1.0f;
    }

    static inline void ke_mat4_mul(ke_mat4 *out, const ke_mat4 *a, const ke_mat4 *b)
    {
        for (int i = 0; i < 4; i++)
        {
            for (int j = 0; j < 4; j++)
            {
                out->m[i * 4 + j] = a->m[i * 4 + 0] * b->m[0 * 4 + j] +
                                    a->m[i * 4 + 1] * b->m[1 * 4 + j] +
                                    a->m[i * 4 + 2] * b->m[2 * 4 + j] +
                                    a->m[i * 4 + 3] * b->m[3 * 4 + j];
            }
        }
    }

    // Simplified transform to matrix (no full quat math for now to keep it core C)
    static inline void ke_mat4_from_transform(ke_mat4 *out, const ke_vec3 *pos, const ke_quat *rot, const ke_vec3 *scale)
    {
        ke_mat4_identity(out);
        // Translation
        out->m[12] = pos->x;
        out->m[13] = pos->y;
        out->m[14] = pos->z;

        // Rotation placeholder (identity for now)
        // Scale
        out->m[0] *= scale->x;
        out->m[5] *= scale->y;
        out->m[10] *= scale->z;
    }

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_COMMON_MATH_H_

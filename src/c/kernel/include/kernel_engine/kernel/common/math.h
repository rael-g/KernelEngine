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

    /// @brief Builds a row-major TRS matrix from position, quaternion rotation, and scale.
    static inline void ke_mat4_from_transform(ke_mat4 *out, const ke_vec3 *pos, const ke_quat *rot, const ke_vec3 *scale)
    {
        float qx = rot->x, qy = rot->y, qz = rot->z, qw = rot->w;

        float r00 = 1.0f - 2.0f * (qy*qy + qz*qz);
        float r01 = 2.0f * (qx*qy + qz*qw);
        float r02 = 2.0f * (qx*qz - qy*qw);

        float r10 = 2.0f * (qx*qy - qz*qw);
        float r11 = 1.0f - 2.0f * (qx*qx + qz*qz);
        float r12 = 2.0f * (qy*qz + qx*qw);

        float r20 = 2.0f * (qx*qz + qy*qw);
        float r21 = 2.0f * (qy*qz - qx*qw);
        float r22 = 1.0f - 2.0f * (qx*qx + qy*qy);

        out->m[0]  = r00 * scale->x; out->m[1]  = r01 * scale->x; out->m[2]  = r02 * scale->x; out->m[3]  = 0.0f;
        out->m[4]  = r10 * scale->y; out->m[5]  = r11 * scale->y; out->m[6]  = r12 * scale->y; out->m[7]  = 0.0f;
        out->m[8]  = r20 * scale->z; out->m[9]  = r21 * scale->z; out->m[10] = r22 * scale->z; out->m[11] = 0.0f;
        out->m[12] = pos->x;         out->m[13] = pos->y;         out->m[14] = pos->z;         out->m[15] = 1.0f;
    }

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_COMMON_MATH_H_

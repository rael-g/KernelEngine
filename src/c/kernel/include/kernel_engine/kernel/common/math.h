#ifndef KERNEL_ENGINE_KERNEL_COMMON_MATH_H_
#define KERNEL_ENGINE_KERNEL_COMMON_MATH_H_

#include <string.h>
#include <math.h>

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
        ke_mat4 res;
        for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 4; j++) {
                res.m[i * 4 + j] = a->m[i * 4 + 0] * b->m[0 * 4 + j] +
                                   a->m[i * 4 + 1] * b->m[1 * 4 + j] +
                                   a->m[i * 4 + 2] * b->m[2 * 4 + j] +
                                   a->m[i * 4 + 3] * b->m[3 * 4 + j];
            }
        }
        memcpy(out->m, res.m, sizeof(float) * 16);
    }

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

    static inline void ke_mat4_inv(ke_mat4 *out, const ke_mat4 *m)
    {
        // Simple matrix inversion for TRS (transpose rotation, negative translation)
        // For general inversion we'd need a more robust algo, but TRS covers 99% of nodes
        ke_mat4 res;
        // Transpose 3x3 rotation
        res.m[0] = m->m[0]; res.m[1] = m->m[4]; res.m[2] = m->m[8]; res.m[3] = 0.0f;
        res.m[4] = m->m[1]; res.m[5] = m->m[5]; res.m[6] = m->m[9]; res.m[7] = 0.0f;
        res.m[8] = m->m[2]; res.m[9] = m->m[6]; res.m[10]= m->m[10];res.m[11]= 0.0f;
        // Inverse translation
        float tx = m->m[12], ty = m->m[13], tz = m->m[14];
        res.m[12] = -(tx * res.m[0] + ty * res.m[4] + tz * res.m[8]);
        res.m[13] = -(tx * res.m[1] + ty * res.m[5] + tz * res.m[9]);
        res.m[14] = -(tx * res.m[2] + ty * res.m[6] + tz * res.m[10]);
        res.m[15] = 1.0f;
        memcpy(out->m, res.m, sizeof(float) * 16);
    }

    static inline void ke_mat4_proj(ke_mat4 *out, float fov, float aspect, float near_z, float far_z)
    {
        float f = 1.0f / tanf(fov * 0.5f);
        memset(out->m, 0, sizeof(float) * 16);
        out->m[0] = f / aspect;
        out->m[5] = f;
        // Right-handed, Vulkan depth [0,1]: w_clip = -vz, so objects at -Z are in front.
        out->m[10] = -far_z / (far_z - near_z);
        out->m[11] = -1.0f;
        out->m[14] = -(far_z * near_z) / (far_z - near_z);
    }

    static inline void ke_mat4_ortho(ke_mat4 *out, float left, float right, float bottom, float top, float near_z, float far_z)
    {
        memset(out->m, 0, sizeof(float) * 16);
        out->m[0] = 2.0f / (right - left);
        out->m[5] = 2.0f / (top - bottom);
        out->m[10] = 1.0f / (far_z - near_z);
        out->m[12] = -(right + left) / (right - left);
        out->m[13] = -(top + bottom) / (top - bottom);
        out->m[14] = -near_z / (far_z - near_z);
        out->m[15] = 1.0f;
    }

    static inline void ke_mat4_lookat(ke_mat4 *out, const ke_vec3 *eye, const ke_vec3 *at, const ke_vec3 *up)
    {
        ke_vec3 z = {at->x - eye->x, at->y - eye->y, at->z - eye->z};
        float len = sqrtf(z.x*z.x + z.y*z.y + z.z*z.z);
        z.x /= len; z.y /= len; z.z /= len;

        ke_vec3 x = {up->y * z.z - up->z * z.y, up->z * z.x - up->x * z.z, up->x * z.y - up->y * z.x};
        len = sqrtf(x.x*x.x + x.y*x.y + x.z*x.z);
        x.x /= len; x.y /= len; x.z /= len;

        ke_vec3 y = {z.y * x.z - z.z * x.y, z.z * x.x - z.x * x.z, z.x * x.y - z.y * x.x};

        ke_mat4 res;
        ke_mat4_identity(&res);
        res.m[0] = x.x; res.m[4] = x.y; res.m[8] = x.z;
        res.m[1] = y.x; res.m[5] = y.y; res.m[9] = y.z;
        res.m[2] = z.x; res.m[6] = z.y; res.m[10]= z.z;
        res.m[12] = -(x.x * eye->x + x.y * eye->y + x.z * eye->z);
        res.m[13] = -(y.x * eye->x + y.y * eye->y + y.z * eye->z);
        res.m[14] = -(z.x * eye->x + z.y * eye->y + z.z * eye->z);
        memcpy(out->m, res.m, sizeof(float) * 16);
    }

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_COMMON_MATH_H_

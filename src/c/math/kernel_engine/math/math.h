#ifndef KERNEL_ENGINE_MATH_MATH_H_
#define KERNEL_ENGINE_MATH_MATH_H_

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_vec2 { float x, y;       } ke_vec2;
    typedef struct ke_vec3 { float x, y, z;    } ke_vec3;
    typedef struct ke_vec4 { float x, y, z, w; } ke_vec4;
    typedef struct ke_quat { float x, y, z, w; } ke_quat;

    typedef struct ke_mat4 { float m[16]; } ke_mat4;

    /** [value] Spatial transform: where a thing is, how it is turned, and how big it is. */
    typedef struct ke_transform
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
    } ke_transform;

#ifdef __cplusplus
}
#endif

#endif

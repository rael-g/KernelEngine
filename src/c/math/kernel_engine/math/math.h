#ifndef KERNEL_ENGINE_MATH_MATH_H_
#define KERNEL_ENGINE_MATH_MATH_H_

#ifdef __cplusplus
extern "C"
{
#endif

    /** [vector] Two floats, x then y. */
    typedef struct ke_vec2 { float x, y;       } ke_vec2;
    /** [vector] Three floats, x then y then z. */
    typedef struct ke_vec3 { float x, y, z;    } ke_vec3;
    /** [vector] Four floats, x then y then z then w. */
    typedef struct ke_vec4 { float x, y, z, w; } ke_vec4;
    /** [quaternion] A rotation; the four lanes are x, y, z, w. */
    typedef struct ke_quat { float x, y, z, w; } ke_quat;

    /** [matrix] Sixteen floats. */
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

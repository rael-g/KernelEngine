#ifndef KERNEL_ENGINE_SPATIAL_TRANSFORM_H_
#define KERNEL_ENGINE_SPATIAL_TRANSFORM_H_

#include <kernel_engine/math/math.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [node:Node3D,value]
    /// An entity's authored 3D pose.
    typedef struct ke_transform_component
    {
        ke_vec3 position;
        ke_quat rotation; ///< [default:0 0 0 1]
        ke_vec3 scale; ///< [default:1 1 1]
    } ke_transform_component;

    /// [node:Node2D]
    /// An entity's authored 2D pose, read and written as one unit.
    typedef struct ke_transform2d_component
    {
        ke_vec2 position;
        float   rotation; ///< Radians, CCW positive; a scene authors degrees.
        ke_vec2 scale; ///< [default:1 1]
        float   depth; ///< Where the plane sits along Z.
    } ke_transform2d_component;

    /// [value]
    /// An entity's place in world space, composed down the hierarchy. Written by
    /// the hierarchy alone.
    typedef struct ke_world_transform_component
    {
        ke_mat4 matrix; ///< [output]
    } ke_world_transform_component;

#ifdef __cplusplus
}
#endif

#endif

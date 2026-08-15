#ifndef KERNEL_ENGINE_SPATIAL_TRANSFORM_H_
#define KERNEL_ENGINE_SPATIAL_TRANSFORM_H_

#include <kernel_engine/common/math.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [node:Node3D,whole:LocalTransform=KernelEngine.Ecs.TransformComponent,default:KernelEngine.Ecs.TransformComponent.Identity]
    /// An entity's authored 3D pose, read and written as one unit.
    typedef struct ke_transform_component
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
    } ke_transform_component;

#define KE_COMPONENT_NAME_TRANSFORM "transform"

    /// [node:Node2D]
    /// An entity's authored 2D pose, read and written as one unit.
    typedef struct ke_transform2d_component
    {
        ke_vec2 position;
        float   rotation; ///< Radians, CCW positive; a scene authors degrees.
        ke_vec2 scale; ///< [default:1 1]
        float   depth; ///< Where the plane sits along Z.
    } ke_transform2d_component;

#define KE_COMPONENT_NAME_TRANSFORM_2D "transform2d"

    /// An entity's place in world space, composed down the hierarchy. Written by
    /// the hierarchy alone.
    typedef struct ke_world_transform_component
    {
        ke_mat4 matrix; ///< [output]
    } ke_world_transform_component;

#define KE_COMPONENT_NAME_WORLD_TRANSFORM "world_transform"

#ifdef __cplusplus
}
#endif

#endif

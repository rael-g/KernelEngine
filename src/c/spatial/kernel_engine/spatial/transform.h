#ifndef KERNEL_ENGINE_SPATIAL_TRANSFORM_H_
#define KERNEL_ENGINE_SPATIAL_TRANSFORM_H_

#include <kernel_engine/common/math.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [node:Node3D,whole:LocalTransform=KernelEngine.Ecs.TransformComponent,default:KernelEngine.Ecs.TransformComponent.Identity]
    /// Per-entity authored 3D pose. Read/written as one atomic unit (position,
    /// rotation, and scale are meaningless set independently mid-write) — kabic's
    /// [whole:] tag maps the whole struct to a single bit-cast property instead of
    /// one property per field. Carries only what a caller writes: the resolved
    /// world matrix is ke_world_transform_component, so no consumer of a pose is
    /// handed a derived field it is free to overwrite.
    typedef struct ke_transform_component
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
    } ke_transform_component;

#define KE_COMPONENT_NAME_TRANSFORM "transform"

    /// [node:Node2D]
    /// Per-entity authored 2D pose. A node placed in a plane says so: it carries
    /// two axes and one angle, and can no longer be handed a quaternion or a
    /// third scale axis by accident. Depth is where the plane sits along Z — the
    /// same axis the depth test and the transparent sort read, so two blended
    /// sprites order by an authored value instead of by storage order.
    typedef struct ke_transform2d_component
    {
        ke_vec2 position;
        /// Radians, CCW positive. A scene authors degrees, as it does in 3D.
        float   rotation;
        ke_vec2 scale; ///< [default:1 1]
        float   depth;
    } ke_transform2d_component;

#define KE_COMPONENT_NAME_TRANSFORM_2D "transform2d"

    /// Where an entity ended up in world space, composed down the hierarchy from
    /// every ancestor's authored pose. The hierarchy is its only writer. It is a
    /// component of its own so a consumer that needs nothing but the resolved
    /// matrix declares exactly that, and never learns in how many dimensions the
    /// pose behind it was authored.
    typedef struct ke_world_transform_component
    {
        ke_mat4 matrix; ///< [output]
    } ke_world_transform_component;

#define KE_COMPONENT_NAME_WORLD_TRANSFORM "world_transform"

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_SPATIAL_TRANSFORM_H_

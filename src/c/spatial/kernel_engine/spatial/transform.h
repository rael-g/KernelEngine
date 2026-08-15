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

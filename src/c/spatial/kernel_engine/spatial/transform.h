#ifndef KERNEL_ENGINE_SPATIAL_TRANSFORM_H_
#define KERNEL_ENGINE_SPATIAL_TRANSFORM_H_

#include <kernel_engine/common/math.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [node:Node3D,whole:LocalTransform=KernelEngine.Ecs.TransformComponent,default:KernelEngine.Ecs.TransformComponent.Identity]
    /// Per-entity 3D transform component. Read/written as one atomic unit (position,
    /// rotation, and scale are meaningless set independently mid-write) — kabic's
    /// [whole:] tag maps the whole struct to a single bit-cast property instead of
    /// one property per field. world_matrix is derived output, recomputed from the
    /// hierarchy each frame; it rides along in the same atomic struct rather than
    /// being a separate field a caller could plausibly author.
    typedef struct ke_transform_component
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
        ke_mat4 world_matrix;
    } ke_transform_component;

#define KE_COMPONENT_NAME_TRANSFORM "transform"

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_SPATIAL_TRANSFORM_H_

#ifndef KERNEL_ENGINE_SPATIAL_TRANSFORM_H_
#define KERNEL_ENGINE_SPATIAL_TRANSFORM_H_

#include <kernel_engine/common/math.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Per-entity 3D transform component.
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

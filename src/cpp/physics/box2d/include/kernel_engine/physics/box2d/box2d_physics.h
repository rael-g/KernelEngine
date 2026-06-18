#pragma once

#include <kernel_engine/physics/physics_2d.h>
#include <kernel_engine/physics/box2d/physics_export.h>

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Construction parameters for the Box2D-backed ke_physics_2d.
typedef struct ke_physics_2d_box2d_params
{
    struct ke_logger    *logger;       ///< Optional; may be NULL
    float                gravity_x;    ///< Default 0
    float                gravity_y;    ///< Default -9.81
} ke_physics_2d_box2d_params;

/// @brief Creates a Box2D-backed 2D physics world.
KE_PHYSICS_BOX2D_API ke_result ke_physics_2d_box2d_create(
    const ke_physics_2d_box2d_params *params,
    ke_physics_2d_handle *out,
    ke_error **out_error);

#ifdef __cplusplus
}
#endif

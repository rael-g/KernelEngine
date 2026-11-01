#include <stddef.h>
#include <kernel_engine/physics/box2d/box2d_physics.h>
#include <kernel_engine/physics/box2d/physics_2d_box2d_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_physics_2d_box2d_params),
    offsetof(ke_physics_2d_box2d_params, gravity_x),
    offsetof(ke_physics_2d_box2d_params, gravity_y),
    0,
};

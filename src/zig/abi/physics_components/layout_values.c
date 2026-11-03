#include <stddef.h>
#include <kernel_engine/physics/components.h>
const unsigned long long layout_values[] = {
    sizeof(ke_body2d_component),
    offsetof(ke_body2d_component, type),
    offsetof(ke_body2d_component, velocity),
    offsetof(ke_body2d_component, angular_velocity),
    offsetof(ke_body2d_component, gravity_scale),
    offsetof(ke_body2d_component, fixed_rotation),
    offsetof(ke_body2d_component, body),
    sizeof(ke_collider2d_component),
    offsetof(ke_collider2d_component, kind),
    offsetof(ke_collider2d_component, half_extents),
    offsetof(ke_collider2d_component, radius),
    offsetof(ke_collider2d_component, density),
    offsetof(ke_collider2d_component, friction),
    offsetof(ke_collider2d_component, restitution),
    offsetof(ke_collider2d_component, layer),
    offsetof(ke_collider2d_component, mask),
    offsetof(ke_collider2d_component, attached),
    0,
};

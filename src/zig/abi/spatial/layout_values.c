#include <stddef.h>
#include <kernel_engine/spatial/transform.h>
const unsigned long long layout_values[] = {
    sizeof(ke_transform_component),
    offsetof(ke_transform_component, position),
    offsetof(ke_transform_component, rotation),
    offsetof(ke_transform_component, scale),
    sizeof(ke_transform2d_component),
    offsetof(ke_transform2d_component, position),
    offsetof(ke_transform2d_component, rotation),
    offsetof(ke_transform2d_component, scale),
    offsetof(ke_transform2d_component, depth),
    sizeof(ke_world_transform_component),
    offsetof(ke_world_transform_component, matrix),
    0,
};

#include <stddef.h>
#include <kernel_engine/framework/world.h>
const unsigned long long layout_values[] = {
    sizeof(ke_world_params),
    offsetof(ke_world_params, ecs),
    offsetof(ke_world_params, runtime),
    offsetof(ke_world_params, scene_tree),
    offsetof(ke_world_params, signal_bus),
    sizeof(ke_world),
    offsetof(ke_world, handle),
    offsetof(ke_world, ecs),
    offsetof(ke_world, runtime),
    offsetof(ke_world, scene_tree),
    offsetof(ke_world, register_component_fields),
    offsetof(ke_world, get_component_fields),
    offsetof(ke_world, register_component_apply),
    offsetof(ke_world, get_component_apply),
    offsetof(ke_world, register_component_alias),
    offsetof(ke_world, resolve_component),
    sizeof(ke_world_handle),
    offsetof(ke_world_handle, ref),
    offsetof(ke_world_handle, destroy),
    0,
};

#include <stddef.h>
#include <kernel_engine/framework/scene_component_set.h>
#include <kernel_engine/framework/scene_hierarchy.h>
const unsigned long long layout_values[] = {
    sizeof(ke_scene_component_set),
    offsetof(ke_scene_component_set, handle),
    offsetof(ke_scene_component_set, add),
    offsetof(ke_scene_component_set, register_into),
    sizeof(ke_scene_component_set_handle),
    offsetof(ke_scene_component_set_handle, ref),
    offsetof(ke_scene_component_set_handle, destroy),
    sizeof(ke_scene_hierarchy_handle),
    offsetof(ke_scene_hierarchy_handle, ref),
    offsetof(ke_scene_hierarchy_handle, destroy),
    0,
};

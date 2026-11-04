#include <stddef.h>
#include <kernel_engine/framework/scene_tree.h>
const unsigned long long layout_values[] = {
    sizeof(ke_scene_tree),
    offsetof(ke_scene_tree, handle),
    offsetof(ke_scene_tree, root),
    offsetof(ke_scene_tree, create_node),
    offsetof(ke_scene_tree, create_node_deferred),
    offsetof(ke_scene_tree, destroy_node),
    offsetof(ke_scene_tree, destroy_node_deferred),
    offsetof(ke_scene_tree, destroy_all),
    offsetof(ke_scene_tree, find_node),
    offsetof(ke_scene_tree, parent),
    offsetof(ke_scene_tree, first_child),
    offsetof(ke_scene_tree, next_sibling),
    offsetof(ke_scene_tree, propagate_transforms),
    offsetof(ke_scene_tree, children_first),
    offsetof(ke_scene_tree, hierarchy_generation),
    sizeof(ke_scene_tree_handle),
    offsetof(ke_scene_tree_handle, ref),
    offsetof(ke_scene_tree_handle, destroy),
    0,
};

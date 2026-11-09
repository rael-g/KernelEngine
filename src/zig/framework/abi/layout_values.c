#include <stddef.h>
#include <kernel_engine/framework/asset_resolver_create.h>
#include <kernel_engine/framework/framework_log.h>
#include <kernel_engine/framework/input_actions_create.h>
#include <kernel_engine/framework/scene_hierarchy_create.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/framework/node_types_create.h>
#include <kernel_engine/framework/scene_files_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_input_actions_config),
    offsetof(ke_input_actions_config, section),
    0,
};

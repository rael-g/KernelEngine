#include <stddef.h>
#include <kernel_engine/framework/asset_resolver_create.h>
#include <kernel_engine/framework/framework_log.h>
#include <kernel_engine/framework/input_actions_create.h>
#include <kernel_engine/framework/scene_component_set_create.h>
#include <kernel_engine/framework/scene_hierarchy_create.h>
#include <kernel_engine/framework/scene_loader_create.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/framework/script_host_create.h>
#include <kernel_engine/framework/signal_bus_create.h>
#include <kernel_engine/framework/component_registry_create.h>
#include <kernel_engine/framework/node_types_create.h>
#include <kernel_engine/framework/scene_files_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_input_actions_config),
    offsetof(ke_input_actions_config, section),
    sizeof(ke_script_host_params),
    offsetof(ke_script_host_params, max_types),
    sizeof(ke_signal_bus_params),
    offsetof(ke_signal_bus_params, max_signals),
    offsetof(ke_signal_bus_params, max_connections),
    offsetof(ke_signal_bus_params, max_events),
    offsetof(ke_signal_bus_params, max_deliveries),
    offsetof(ke_signal_bus_params, payload_capacity),
    0,
};

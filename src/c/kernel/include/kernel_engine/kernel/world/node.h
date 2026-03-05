#ifndef KERNEL_ENGINE_KERNEL_WORLD_NODE_H_
#define KERNEL_ENGINE_KERNEL_WORLD_NODE_H_

// ke_node and ke_scene have been removed in favour of the ECS-based node system.
// Use ke_world::create_node / ke_world::destroy_node and the built-in ECS components:
//   ke_transform_component, ke_hierarchy_component, ke_name_component, ke_script_component
//
// See: kernel_engine/kernel/world/components.h
//      kernel_engine/kernel/world/world.h

#include <kernel_engine/kernel/world/components.h>

#endif // KERNEL_ENGINE_KERNEL_WORLD_NODE_H_

#ifndef KERNEL_ENGINE_FRAMEWORK_NODE_TYPE_REGISTRY_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_NODE_TYPE_REGISTRY_CREATE_H_

// Factory for the default ke_node_type_registry implementation — open-addressed
// table of node type descriptors, keyed by string name. Lives in the
// node_type_registry plugin (src/cpp/framework/node_type_registry/) so consumers
// who only want the contract can skip linking the impl.

#include <kernel_engine/framework/node_type_registry.h>
#include <kernel_engine/framework/node_type_registry_export.h>

#ifdef __cplusplus
extern "C"
{
#endif

    KE_NODE_TYPE_REGISTRY_API ke_result ke_node_type_registry_create(
        ke_allocator           *alloc,
        ke_node_type_registry **out_registry);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_NODE_TYPE_REGISTRY_CREATE_H_

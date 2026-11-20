#ifndef KERNEL_ENGINE_ENGINE_NODES_ENGINE_NODES_CREATE_H_
#define KERNEL_ENGINE_ENGINE_NODES_ENGINE_NODES_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/assembly/part.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_ENGINE_NODES_API
#  ifdef KE_ENGINE_NODES_EXPORT
#    define KE_ENGINE_NODES_API KE_EXPORT
#  else
#    define KE_ENGINE_NODES_API KE_IMPORT
#  endif
#endif

/**
 * Registers every type of ke_engine_node_types through @p types, each with the components its `with` describes.
 * @param types [borrowed] The node types the types are registered in, where they stay.
 * @param out_owner [out] Receives an owner whose destroy releases nothing: node types are not unregistered. Left
 *        zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; the node types' code for a type it refuses, the
 *         types registered before it staying.
 */
KE_ENGINE_NODES_API ke_result ke_engine_nodes_create(ke_node_types *types, ke_owner *out_owner);

#ifdef __cplusplus
}
#endif

#endif

#ifndef KERNEL_ENGINE_PHYSICS_BODY2D_PHYSICS_NODES_CREATE_H_
#define KERNEL_ENGINE_PHYSICS_BODY2D_PHYSICS_NODES_CREATE_H_

#include <kernel_engine/physics/body2d/body2d_module.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Registers every type of `ke_physics_node_types` through @p types, each with the components its `with` describes.
    /// @param types [borrowed] The node types the types are registered in, where they stay.
    /// @param out_owner [out] Receives an owner whose destroy releases nothing: node types are not unregistered.
    ///        Left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; the node types' code for a type it refuses,
    ///         the types registered before it staying.
    KE_PHYSICS_BODY2D_API ke_result ke_physics_nodes_create(ke_node_types *types, ke_owner *out_owner);

#ifdef __cplusplus
}
#endif

#endif

#ifndef KERNEL_ENGINE_RENDER_SCENE_RENDER_NODES_CREATE_H_
#define KERNEL_ENGINE_RENDER_SCENE_RENDER_NODES_CREATE_H_

#include <kernel_engine/render/scene/scene_resolve_create.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Registers every type of `ke_render_node_types` through @p types, each with the components its `with` describes.
    /// @param types [borrowed] The node types the types are registered in, where they stay.
    /// @param out_owner [out] Receives an owner whose destroy releases nothing: node types are not unregistered.
    ///        Left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; the node types' code for a type it refuses,
    ///         the types registered before it staying.
    KE_RENDER_SCENE_API ke_result ke_render_nodes_create(ke_node_types *types, ke_owner *out_owner);

#ifdef __cplusplus
}
#endif

#endif

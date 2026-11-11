#ifndef KERNEL_ENGINE_SDK_NODE_H_
#define KERNEL_ENGINE_SDK_NODE_H_

#include <kernel_engine/framework/node_types.h>

#include <stddef.h>

/**
 * @file
 * The node calls a C behaviour writes most: reach a node's component by its name, spawn a node of a
 * type with the component it is named after, and declare that a node type extends an engine node.
 */

/**
 * Declares, inside a `ke_node_type_desc`, that the type extends the engine node whose `with` array is
 * @p base_with (`ke_body2d_node_with`): its nodes carry what that node carries, born as it is born.
 */
#define KE_NODE_EXTENDS(base_with) .with = (base_with), .with_count = (uint32_t)(sizeof(base_with) / sizeof((base_with)[0]))

/**
 * The component registered under @p component of @p node.
 * @param component [utf8] A `KE_COMPONENT_NAME_*` constant, or a name the game registered.
 * @return The component's memory, NULL for an invalid node, an unknown name or a node that does not carry it.
 */
static inline void *ke_sdk_get(ke_node_ctx *ctx, ke_entity node, const char *component)
{
    ke_component_id id = KE_COMPONENT_INVALID;
    if (node == KE_ENTITY_INVALID || ctx->find_component(ctx, component, &id) != KE_OK) return NULL;
    return ctx->component(ctx, node, id);
}

/**
 * Records under the current node a node named @p name of the type registered as @p type, holding
 * @p data in place of its type's initial value of the component of the same name.
 * @param type [utf8] An engine node type, named after its component (`KE_COMPONENT_NAME_SOUND`).
 * @param name [utf8]
 * @param data [bytes_of:size] The component's value, copied.
 * @return KE_OK, or the code of the lookup or the spawn that failed.
 */
static inline ke_result ke_sdk_spawn(ke_node_ctx *ctx, const char *type, const char *name, const void *data, size_t size)
{
    ke_component_id type_id = KE_COMPONENT_INVALID;
    ke_component_id component_id = KE_COMPONENT_INVALID;
    ke_result found = ctx->find_type(ctx, type, &type_id);
    if (found == KE_OK) found = ctx->find_component(ctx, type, &component_id);
    if (found != KE_OK) return found;
    const ke_node_component components[] = { { component_id, data, size } };
    ke_entity node = KE_ENTITY_INVALID;
    return ctx->spawn(ctx, type_id, name, ctx->self, components, 1, &node);
}

#endif

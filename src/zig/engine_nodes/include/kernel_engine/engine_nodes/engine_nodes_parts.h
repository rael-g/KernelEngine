#ifndef KERNEL_ENGINE_ENGINE_NODES_ENGINE_NODES_PARTS_H_
#define KERNEL_ENGINE_ENGINE_NODES_ENGINE_NODES_PARTS_H_

#include <kernel_engine/engine_nodes/engine_nodes_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_engine_nodes contains: `engine_nodes`, providing nothing, with the slot `types`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_ENGINE_NODES_API const ke_part *ke_engine_nodes_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

#ifndef KERNEL_ENGINE_RENDER_GRAPH_SIMPLE_RENDER_GRAPH_SIMPLE_PARTS_H_
#define KERNEL_ENGINE_RENDER_GRAPH_SIMPLE_RENDER_GRAPH_SIMPLE_PARTS_H_

#include <kernel_engine/render_graph/simple/render_graph_simple_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_graph_simple contains: `render_graph_simple`, providing ke_render_graph, with the
 * slot `device`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_GRAPH_SIMPLE_API const ke_part *ke_render_graph_simple_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

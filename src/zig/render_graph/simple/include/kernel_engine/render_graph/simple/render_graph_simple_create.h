#ifndef KERNEL_ENGINE_RENDER_GRAPH_SIMPLE_RENDER_GRAPH_SIMPLE_CREATE_H_
#define KERNEL_ENGINE_RENDER_GRAPH_SIMPLE_RENDER_GRAPH_SIMPLE_CREATE_H_

#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render_graph/render_graph.h>
#include <kernel_engine/render_graph/simple/render_graph_simple_log.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Creates a render graph over @p device that executes on the calling thread, one frame at a time, leaving the
 * transitions to the device. It offers no acceleration structure, readback, resolve or generated mips.
 * @param device [borrowed] Must outlive the graph.
 * @param out_graph [out] Receives the graph; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_OUT_OF_MEMORY.
 */
KE_RENDER_GRAPH_SIMPLE_API ke_result ke_render_graph_simple_create(
    ke_gpu_device          *device,
    ke_render_graph_handle *out_graph);

#ifdef __cplusplus
}
#endif

#endif

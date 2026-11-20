#ifndef KERNEL_ENGINE_RENDER_GBUFFER_RENDER_GBUFFER_PARTS_H_
#define KERNEL_ENGINE_RENDER_GBUFFER_RENDER_GBUFFER_PARTS_H_

#include <kernel_engine/render/gbuffer/gbuffer_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_gbuffer contains: `render_gbuffer`, providing nothing, with the slots `service`,
 * `device`, `frame`, `scene`, `render_prepare` and `render_queue`, `render_prepare` and `render_queue` the
 * ke_schedule_sets its systems join.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_GBUFFER_API const ke_part *ke_render_gbuffer_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

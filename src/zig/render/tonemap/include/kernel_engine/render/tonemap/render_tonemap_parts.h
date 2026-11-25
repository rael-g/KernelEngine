#ifndef KERNEL_ENGINE_RENDER_TONEMAP_RENDER_TONEMAP_PARTS_H_
#define KERNEL_ENGINE_RENDER_TONEMAP_RENDER_TONEMAP_PARTS_H_

#include <kernel_engine/render/tonemap/tonemap_create.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_tonemap contains: `render_tonemap`, providing nothing, with the slots `service`,
 * `device`, `frame` and `render_queue`, `render_queue` the ke_schedule_set its systems join.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_TONEMAP_API const ke_part *ke_render_tonemap_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

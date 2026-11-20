#ifndef KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_RENDER_DEFERRED_LIGHTING_PARTS_H_
#define KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_RENDER_DEFERRED_LIGHTING_PARTS_H_

#include <kernel_engine/render/deferred_lighting/deferred_lighting_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_deferred_lighting contains: `render_deferred_lighting`, providing nothing, with the
 * slots `service`, `device`, `frame`, `scene` and `render_queue`, `render_queue` the ke_schedule_set its systems
 * join.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_DEFERRED_LIGHTING_API const ke_part *ke_render_deferred_lighting_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

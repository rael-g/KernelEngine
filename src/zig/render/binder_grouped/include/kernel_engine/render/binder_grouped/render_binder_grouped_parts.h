#ifndef KERNEL_ENGINE_RENDER_BINDER_GROUPED_RENDER_BINDER_GROUPED_PARTS_H_
#define KERNEL_ENGINE_RENDER_BINDER_GROUPED_RENDER_BINDER_GROUPED_PARTS_H_

#include <kernel_engine/render/binder_grouped/resource_binder_grouped_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_binder_grouped contains: `render_binder_grouped`, providing
 * ke_render_resource_binder, with the slots `device` and `io`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_BINDER_GROUPED_API const ke_part *ke_render_binder_grouped_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

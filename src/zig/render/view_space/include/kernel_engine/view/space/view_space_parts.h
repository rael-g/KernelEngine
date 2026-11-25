#ifndef KERNEL_ENGINE_VIEW_SPACE_VIEW_SPACE_PARTS_H_
#define KERNEL_ENGINE_VIEW_SPACE_VIEW_SPACE_PARTS_H_

#include <kernel_engine/view/space/view_space_lh_create.h>
#include <kernel_engine/view/space/view_space_rh_create.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_view_space contains, each named after its factory and with its slots named after the
 * factory's parameters: `view_space_rh` (ke_view_space); `view_space_lh` (ke_view_space).
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_VIEW_SPACE_API const ke_part *ke_view_space_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

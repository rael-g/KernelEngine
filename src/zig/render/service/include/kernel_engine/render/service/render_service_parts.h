#ifndef KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_PARTS_H_
#define KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_PARTS_H_

#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_service contains: `render_service`, providing ke_render_service, with the slots
 * `device`, `target`, `io` and `binder`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_CORE_API const ke_part *ke_render_service_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

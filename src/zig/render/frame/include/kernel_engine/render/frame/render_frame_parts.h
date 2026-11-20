#ifndef KERNEL_ENGINE_RENDER_FRAME_RENDER_FRAME_PARTS_H_
#define KERNEL_ENGINE_RENDER_FRAME_RENDER_FRAME_PARTS_H_

#include <kernel_engine/render/frame/frame_create.h>
#include <kernel_engine/render/frame/frame_systems_create.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_frame contains, each named after its factory and with its slots named after the
 * factory's parameters: `render_frame` (ke_render_frame; `ecs`, `graph`, `service`, `camera` and `scene`);
 * `render_frame_systems` (nothing; `frame`, `render_begin` and `render_submit`).
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_FRAME_API const ke_part *ke_render_frame_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

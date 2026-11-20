#ifndef KERNEL_ENGINE_RENDER_SCENE_RENDER_SCENE_PARTS_H_
#define KERNEL_ENGINE_RENDER_SCENE_RENDER_SCENE_PARTS_H_

#include <kernel_engine/render/scene/label_resolve_create.h>
#include <kernel_engine/render/scene/scene_resolve_create.h>
#include <kernel_engine/render/scene/scene_resolve_systems_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_scene contains, each named after its factory and with its slots named after the
 * factory's parameters: `render_scene_resolve` (ke_render_scene_resolve; `main`, `render`, `extraction`,
 * `service` and `resolver`, optional); `render_scene_resolve_systems` (nothing; `scene`, `update` and
 * `post_update`); `render_label_resolve` (nothing; `service`, `scene`, `ui`, `resolver`, optional, and `update`).
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_SCENE_API const ke_part *ke_render_scene_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

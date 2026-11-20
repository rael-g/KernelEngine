#ifndef KERNEL_ENGINE_RENDER_UI_RENDER_UI_PARTS_H_
#define KERNEL_ENGINE_RENDER_UI_RENDER_UI_PARTS_H_

#include <kernel_engine/render/ui/ui_create.h>
#include <kernel_engine/render/ui/ui_systems_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_ui contains, each named after its factory and with its slots named after the
 * factory's parameters: `render_ui` (ke_render_ui; `main`, `render`, `extraction`, `service`, `device` and
 * `frame`); `render_ui_systems` (nothing; `ui`, `render_prepare` and `render_queue`).
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_UI_API const ke_part *ke_render_ui_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

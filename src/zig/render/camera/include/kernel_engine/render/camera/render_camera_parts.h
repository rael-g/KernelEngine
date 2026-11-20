#ifndef KERNEL_ENGINE_RENDER_CAMERA_RENDER_CAMERA_PARTS_H_
#define KERNEL_ENGINE_RENDER_CAMERA_RENDER_CAMERA_PARTS_H_

#include <kernel_engine/render/camera/camera_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_render_camera contains: `render_camera`, providing ke_render_camera, with the slots
 * `view_space` and `device`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RENDER_CAMERA_API const ke_part *ke_render_camera_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

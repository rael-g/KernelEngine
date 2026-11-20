#ifndef KERNEL_ENGINE_RENDER_WEBGPU_GPU_DEVICE_WEBGPU_PARTS_H_
#define KERNEL_ENGINE_RENDER_WEBGPU_GPU_DEVICE_WEBGPU_PARTS_H_

#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_gpu_device_webgpu contains, each named after its factory and with its slots named after the
 * factory's parameters: `gpu_device_webgpu` (ke_gpu_device; `async`, optional);
 * `gpu_render_target_webgpu_window` (ke_gpu_render_target; `device` and `window`).
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_GPU_WEBGPU_API const ke_part *ke_gpu_device_webgpu_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif

#ifndef KERNEL_ENGINE_RENDER_GPU_GPU_RENDER_TARGET_H_
#define KERNEL_ENGINE_RENDER_GPU_GPU_RENDER_TARGET_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/gpu/gpu_device.h>

#ifdef __cplusplus
extern "C"
{
#endif

/// The surface a frame is drawn into. A frame is one acquire followed, once the frame's command
/// buffers were submitted, by one present.
typedef struct ke_gpu_render_target
{
    void *handle;

    /// Begins a frame and writes the view to draw into, owned by the target and valid until
    /// present. Succeeds writing KE_GPU_INVALID_HANDLE when the target has nothing to draw into
    /// this frame, and fails writing it when acquiring failed.
    /// @param out_view [out] Receives the view.
    ke_result (*acquire)(struct ke_gpu_render_target *self, ke_gpu_texture_view *out_view);

    /// Ends the frame begun by acquire. Fails with KE_RESULT_INVALID_ARGUMENT when no frame is
    /// acquired.
    ke_result (*present)(struct ke_gpu_render_target *self);

    /// Size in pixels of the view the last acquire returned, or of the next one before any acquire.
    void (*size)(struct ke_gpu_render_target *self, uint32_t *out_width, uint32_t *out_height);

    /// Texel format of every view acquire returns.
    ke_gpu_texture_format (*format)(struct ke_gpu_render_target *self);
} ke_gpu_render_target;

typedef struct ke_gpu_render_target_handle
{
    ke_gpu_render_target *ref;
    void (*destroy)(ke_gpu_render_target *self);
} ke_gpu_render_target_handle;

#ifdef __cplusplus
}
#endif

#endif

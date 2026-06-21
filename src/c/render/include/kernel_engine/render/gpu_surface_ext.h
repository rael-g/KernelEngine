#ifndef KERNEL_ENGINE_RENDER_GPU_SURFACE_EXT_H_
#define KERNEL_ENGINE_RENDER_GPU_SURFACE_EXT_H_

#include <kernel_engine/render/gpu_enums.h>

#ifdef __cplusplus
extern "C"
{
#endif

/// Extension name for ke_gpu_device::query_extension.
#define KE_GPU_SURFACE_EXT_NAME "ke_gpu_surface_ext"

/// Extension vtable returned by query_extension("ke_gpu_surface_ext").
/// Only available when the device was created with a non-NULL ke_window.
typedef struct ke_gpu_surface_ext
{
    /// Acquire the current swapchain texture view.
    /// Returns KE_GPU_INVALID_HANDLE if the surface is not ready (e.g. minimised).
    /// The returned view is owned by the caller; destroy it with destroy_texture_view
    /// before calling acquire_current_texture_view again.
    ke_gpu_texture_view (*acquire_current_texture_view)(const struct ke_gpu_surface_ext *self);

    /// Reconfigure the swapchain to a new size. Call after a window resize.
    void (*reconfigure)(const struct ke_gpu_surface_ext *self, uint32_t width, uint32_t height);
} ke_gpu_surface_ext;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_GPU_SURFACE_EXT_H_

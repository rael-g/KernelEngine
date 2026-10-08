#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_render_target.h>

struct ke_window;

#ifndef KE_GPU_WEBGPU_API
#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_GPU_WEBGPU_EXPORT
        #define KE_GPU_WEBGPU_API __declspec(dllexport)
    #elif defined(KE_GPU_WEBGPU_STATIC)
        #define KE_GPU_WEBGPU_API
    #else
        #define KE_GPU_WEBGPU_API __declspec(dllimport)
    #endif
#else
    #define KE_GPU_WEBGPU_API __attribute__((visibility("default")))
#endif
#endif

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * @brief Creates a render target presenting into a window, sized to the window's client area.
 * @param device A device created by ke_gpu_device_webgpu_create; borrowed, must outlive the target.
 * @param window Borrowed, must outlive the target.
 * @return Handle whose @c ref is NULL on failure: KE_ERROR_INVALID_ARGUMENT for a device from
 *         another backend or a NULL window, KE_ERROR_NOT_SUPPORTED when the window's surface offers
 *         neither an RGBA8 nor a BGRA8 format.
 */
KE_GPU_WEBGPU_API ke_gpu_render_target_handle
ke_gpu_render_target_webgpu_window_create(ke_gpu_device *device, struct ke_window *window,
                                          ke_error **out_error);

#ifdef __cplusplus
}
#endif

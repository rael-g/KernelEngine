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

/** How presented frames reach the screen. */
typedef enum ke_gpu_present_mode
{
    /** Each frame waits for the display's vertical blank; no tearing. */
    KE_GPU_PRESENT_MODE_FIFO = 0,
    /** The newest frame replaces the one waiting for the blank; no tearing, no waiting. */
    KE_GPU_PRESENT_MODE_MAILBOX = 1,
    /** Frames are shown at once and may tear. */
    KE_GPU_PRESENT_MODE_IMMEDIATE = 2,
} ke_gpu_present_mode;

/** @brief Parameters for a render target presenting into a window. */
typedef struct ke_gpu_render_target_webgpu_window_params
{
    /** A device created by ke_gpu_device_webgpu_create; borrowed, must outlive the target. */
    ke_gpu_device       *device;
    /** Borrowed, must outlive the target. */
    struct ke_window    *window;
    /** Zero selects KE_GPU_PRESENT_MODE_FIFO. */
    ke_gpu_present_mode  present_mode;
} ke_gpu_render_target_webgpu_window_params;

/**
 * @brief Creates a render target presenting into a window, sized to the window's client area.
 * @return Handle whose @c ref is NULL on failure: KE_ERROR_INVALID_ARGUMENT for null params, a
 *         device from another backend or a NULL window, KE_ERROR_NOT_SUPPORTED when the window's
 *         surface offers neither an RGBA8 nor a BGRA8 format, or does not offer the present mode
 *         asked for.
 */
KE_GPU_WEBGPU_API ke_gpu_render_target_handle
ke_gpu_render_target_webgpu_window_create(const ke_gpu_render_target_webgpu_window_params *params,
                                          ke_error **out_error);

#ifdef __cplusplus
}
#endif

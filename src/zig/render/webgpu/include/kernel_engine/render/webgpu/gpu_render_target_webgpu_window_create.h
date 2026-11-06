#ifndef KERNEL_ENGINE_RENDER_WEBGPU_GPU_RENDER_TARGET_WEBGPU_WINDOW_CREATE_H_
#define KERNEL_ENGINE_RENDER_WEBGPU_GPU_RENDER_TARGET_WEBGPU_WINDOW_CREATE_H_

#include <kernel_engine/result/result.h>
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

/// [bag] The values a window render target is created with, each applied as given.
typedef struct ke_gpu_render_target_webgpu_window_config
{
    /// [default:KE_GPU_PRESENT_MODE_FIFO] How presented frames reach the screen.
    ke_gpu_present_mode present_mode;
} ke_gpu_render_target_webgpu_window_config;

/**
 * @brief Creates a render target presenting into a window, sized to the window's client area.
 * @param device A device created by ke_gpu_device_webgpu_create; borrowed, must outlive the target.
 * @param window [borrowed] The window presented into; must outlive the target.
 * @param config [borrowed,optional] The target's values; NULL selects the default of each.
 * @param out_target [out] Receives the handle; left zeroed on failure.
 * @return KE_OK, or on failure: KE_RESULT_INVALID_ARGUMENT for a device from another backend, a
 *         NULL window or a present mode that is not a ke_gpu_present_mode; KE_RESULT_NOT_SUPPORTED
 *         when the window's surface offers neither an RGBA8 nor a BGRA8 format, or does not offer
 *         the present mode asked for.
 */
KE_GPU_WEBGPU_API ke_result
ke_gpu_render_target_webgpu_window_create(ke_gpu_device *device, struct ke_window *window,
                                          const ke_gpu_render_target_webgpu_window_config *config,
                                          ke_gpu_render_target_handle *out_target);

#ifdef __cplusplus
}
#endif

#endif

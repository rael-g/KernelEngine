#ifndef KERNEL_ENGINE_RENDER_WEBGPU_GPU_RENDER_TARGET_WEBGPU_WINDOW_CREATE_H_
#define KERNEL_ENGINE_RENDER_WEBGPU_GPU_RENDER_TARGET_WEBGPU_WINDOW_CREATE_H_

#include <kernel_engine/settings/settings.h>
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

/**
 * @brief Creates a render target presenting into a window, sized to the window's client area.
 * @param device A device created by ke_gpu_device_webgpu_create; borrowed, must outlive the target.
 * @param window [borrowed] The window presented into; must outlive the target.
 * @param settings [borrowed] Read once. KE_GPU_RENDER_TARGET_SETTING_PRESENT_MODE, default "fifo".
 * @param out_target [out] Receives the handle; left zeroed on failure.
 * @return KE_OK, or on failure: KE_RESULT_INVALID_ARGUMENT for a device from another backend, a
 *         NULL window or settings, or a setting refused; KE_RESULT_NOT_SUPPORTED
 *         when the window's surface offers neither an RGBA8 nor a BGRA8 format, or does not offer
 *         the present mode asked for.
 */
KE_GPU_WEBGPU_API ke_result
ke_gpu_render_target_webgpu_window_create(ke_gpu_device *device, struct ke_window *window,
                                          ke_settings *settings,
                                          ke_gpu_render_target_handle *out_target);

#ifdef __cplusplus
}
#endif

#endif

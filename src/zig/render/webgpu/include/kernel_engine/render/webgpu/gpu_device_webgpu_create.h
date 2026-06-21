#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/render/gpu_device.h>

struct ke_window;

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

#ifdef __cplusplus
extern "C"
{
#endif

/// @brief Parameters for the WebGPU (wgpu-native) GPU device.
typedef struct ke_gpu_device_webgpu_params
{
    struct ke_logger *logger;
    struct ke_window *window;          ///< Optional. When non-NULL, a presentable surface is created.
    ke_bool           enable_validation;
} ke_gpu_device_webgpu_params;

/**
 * @brief Creates a ke_gpu_device backed by WebGPU (wgpu-native).
 * @return Handle whose @c ref is NULL on failure; call @c handle.destroy(handle.ref)
 *         to release when done.
 */
KE_GPU_WEBGPU_API ke_gpu_device_handle
ke_gpu_device_webgpu_create(const ke_gpu_device_webgpu_params *params,
                             ke_error **out_error);

#ifdef __cplusplus
}
#endif

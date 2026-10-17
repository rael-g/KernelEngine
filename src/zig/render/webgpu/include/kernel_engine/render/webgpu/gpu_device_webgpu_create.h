#ifndef KERNEL_ENGINE_RENDER_WEBGPU_GPU_DEVICE_WEBGPU_CREATE_H_
#define KERNEL_ENGINE_RENDER_WEBGPU_GPU_DEVICE_WEBGPU_CREATE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/render/gpu/gpu_device.h>

struct ke_scheduler;

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

/// A shader module failed to compile or validate on this device. Inherits
/// KE_ERROR_GPU_SHADER_COMPILATION; the message carries the validation text.
KE_GPU_WEBGPU_API extern const ke_error_type KE_ERROR_WGPU_SHADER_COMPILATION;

/// A buffer or bind-group creation call was rejected by this device's validation
/// (e.g. a buffer or binding range exceeding this device's limits). Inherits
/// KE_ERROR_GPU_RESOURCE_CREATION; the message carries the validation text.
KE_GPU_WEBGPU_API extern const ke_error_type KE_ERROR_WGPU_RESOURCE_CREATION;

/// @brief Parameters for the WebGPU GPU device.
typedef struct ke_gpu_device_webgpu_params
{
    struct ke_logger    *logger;
    /// When non-zero, asks the underlying graphics API to validate every call, which takes
    /// effect only where that API's validation layers are installed.
    bool                 enable_validation;
    /// Optional, borrowed. When non-NULL, this device dispatches the compile of
    /// create_render_pipeline_async onto this scheduler's worker pool. When NULL,
    /// the compile runs synchronously and the callback is invoked before returning.
    struct ke_scheduler *scheduler;
    /// When non-zero, the labels and debug groups given through ke_gpu_device reach the
    /// underlying graphics API, where capture tools read them.
    bool                 debug_labels;
} ke_gpu_device_webgpu_params;

/**
 * @brief Creates a ke_gpu_device backed by WebGPU.
 * @return Handle whose @c ref is NULL on failure; call @c handle.destroy(handle.ref)
 *         to release when done.
 */
KE_GPU_WEBGPU_API ke_gpu_device_handle
ke_gpu_device_webgpu_create(const ke_gpu_device_webgpu_params *params,
                             ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif

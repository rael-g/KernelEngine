#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/render/gpu_device.h>

struct ke_window;
struct ke_scheduler;

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

/// A shader module failed to compile/validate in wgpu-native. Inherits
/// KE_ERROR_GPU_SHADER_COMPILATION; the message carries the wgpu validation text.
KE_GPU_WEBGPU_API extern const ke_error_type KE_ERROR_WGPU_SHADER_COMPILATION;

/// A buffer/bind-group creation call was rejected by wgpu-native validation
/// (e.g. a buffer or binding range exceeding this device's limits). Inherits
/// KE_ERROR_GPU_RESOURCE_CREATION; the message carries the wgpu validation text.
KE_GPU_WEBGPU_API extern const ke_error_type KE_ERROR_WGPU_RESOURCE_CREATION;

/// @brief Parameters for the WebGPU (wgpu-native) GPU device.
typedef struct ke_gpu_device_webgpu_params
{
    struct ke_logger    *logger;
    struct ke_window    *window;          ///< Optional. When non-NULL, a presentable surface is created.
    ke_bool              enable_validation;
    /// Optional, borrowed. wgpu-native's async pipeline-compile entry points
    /// (wgpuDeviceCreateRenderPipelineAsync et al) are unimplemented upstream
    /// (panic "not implemented") — an implementation-detail limitation of this
    /// backend, not part of ke_gpu_device's contract. When non-NULL, this
    /// device emulates create_render_pipeline_async by dispatching the actual
    /// compile onto this scheduler's worker pool. When NULL, it degrades to a
    /// synchronous compile-then-callback (never hangs, just isn't async).
    struct ke_scheduler *scheduler;
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

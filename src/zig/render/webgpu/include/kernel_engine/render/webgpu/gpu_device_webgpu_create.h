#ifndef KERNEL_ENGINE_RENDER_WEBGPU_GPU_DEVICE_WEBGPU_CREATE_H_
#define KERNEL_ENGINE_RENDER_WEBGPU_GPU_DEVICE_WEBGPU_CREATE_H_

#include <kernel_engine/configuration/configuration.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/render/gpu/gpu_device.h>

struct ke_task_pool;

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

/// [bag] The values a WebGPU device is created with, each applied as given.
typedef struct ke_gpu_device_webgpu_config
{
    /// Asks the underlying graphics API to validate every call, which takes effect
    /// only where that API's validation layers are installed.
    bool enable_validation;
    /// The labels and debug groups given through ke_gpu_device reach the
    /// underlying graphics API, where capture tools read them.
    bool debug_labels;
} ke_gpu_device_webgpu_config;

/** [defaults] The device a caller gets when it sets nothing. */
static const ke_gpu_device_webgpu_config ke_gpu_device_webgpu_config_defaults = {
    .enable_validation = true,
    .debug_labels = false,
};

/** The keys a configuration section fills a ke_gpu_device_webgpu_config from. */
static const ke_config_field ke_gpu_device_webgpu_config_fields[] = {
    KE_CONFIG_FIELD(ke_gpu_device_webgpu_config, enable_validation),
    KE_CONFIG_FIELD(ke_gpu_device_webgpu_config, debug_labels),
};

/**
 * @brief Creates a ke_gpu_device backed by WebGPU.
 * @param task_pool [borrowed,optional] Runs the compile of create_render_pipeline_async on its
 *        workers; NULL compiles synchronously, invoking the callback before returning.
 * @param config [borrowed,optional] The device's values; NULL selects the default of each.
 * @param out_device [out] Receives the handle; left zeroed on failure.
 * @return KE_OK, or a failure code; call @c handle.destroy(handle.ref) to release the handle
 *         when done.
 */
KE_GPU_WEBGPU_API ke_result
ke_gpu_device_webgpu_create(struct ke_task_pool *task_pool, const ke_gpu_device_webgpu_config *config,
                             ke_gpu_device_handle *out_device);

#ifdef __cplusplus
}
#endif

#endif

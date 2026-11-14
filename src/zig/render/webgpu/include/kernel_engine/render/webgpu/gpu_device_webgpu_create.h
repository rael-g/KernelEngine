#ifndef KERNEL_ENGINE_RENDER_WEBGPU_GPU_DEVICE_WEBGPU_CREATE_H_
#define KERNEL_ENGINE_RENDER_WEBGPU_GPU_DEVICE_WEBGPU_CREATE_H_

#include <kernel_engine/completion/completion.h>
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

/**
 * @brief Creates a ke_gpu_device backed by WebGPU.
 * @param task_pool [borrowed,optional] Runs the compile of create_render_pipeline_async on its
 *        workers; NULL compiles synchronously, invoking the callback before returning.
 * @param config [borrowed] The device's values; Required; every field is read as given.
 * @param out_ready [out] Receives the completion that finishes when the device is ready, already
 *        finished since the device is made before the call returns; the caller releases it. Left
 *        NULL on failure.
 * @param out_device [out] Receives the handle; left zeroed on failure.
 * @return KE_OK, or a failure code; call @c handle.destroy(handle.ref) to release the handle
 *         when done.
 */
KE_GPU_WEBGPU_API ke_result
ke_gpu_device_webgpu_create(struct ke_task_pool *task_pool, const ke_gpu_device_config *config,
                             ke_completion **out_ready, ke_gpu_device_handle *out_device);

#ifdef __cplusplus
}
#endif

#endif

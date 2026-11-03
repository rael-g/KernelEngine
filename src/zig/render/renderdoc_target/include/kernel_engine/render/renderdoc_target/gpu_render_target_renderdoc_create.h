#ifndef KERNEL_ENGINE_RENDER_RENDERDOC_TARGET_GPU_RENDER_TARGET_RENDERDOC_CREATE_H_
#define KERNEL_ENGINE_RENDER_RENDERDOC_TARGET_GPU_RENDER_TARGET_RENDERDOC_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/gpu/gpu_render_target.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_GPU_RENDER_TARGET_RENDERDOC_EXPORT
        #define KE_GPU_RENDER_TARGET_RENDERDOC_API __declspec(dllexport)
    #elif defined(KE_GPU_RENDER_TARGET_RENDERDOC_STATIC)
        #define KE_GPU_RENDER_TARGET_RENDERDOC_API
    #else
        #define KE_GPU_RENDER_TARGET_RENDERDOC_API __declspec(dllimport)
    #endif
#else
    #define KE_GPU_RENDER_TARGET_RENDERDOC_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

/// [bag] Which of a render target's frames RenderDoc captures.
typedef struct ke_gpu_render_target_renderdoc_params
{
    /// The first frame captured, counting from zero the frames the target presented.
    uint32_t first_frame;
    /// How many consecutive frames are captured, each into its own capture file.
    uint32_t frame_count;
} ke_gpu_render_target_renderdoc_params;

/**
 * @brief Creates a render target that draws into another one and has RenderDoc capture the chosen
 *        frames, each from its acquire to its present. RenderDoc must already be loaded into the
 *        process. Where the capture files go is set when the process is launched.
 * @param inner Borrowed, must outlive the target; every call is forwarded to it.
 * @return KE_OK, or on failure: KE_RESULT_INVALID_ARGUMENT for a NULL inner target
 *         or params, KE_RESULT_NOT_FOUND when RenderDoc is not loaded into the process.
 * @param out_target [out] Receives the handle; left zeroed on failure.
 */
KE_GPU_RENDER_TARGET_RENDERDOC_API ke_result
ke_gpu_render_target_renderdoc_create(ke_gpu_render_target *inner,
                                      const ke_gpu_render_target_renderdoc_params *params,
                                      ke_gpu_render_target_handle *out_target);

#ifdef __cplusplus
}
#endif

#endif

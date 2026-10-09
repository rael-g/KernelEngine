#pragma once

#include <kernel_engine/common/error.h>
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

/// Which of a render target's frames RenderDoc captures.
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
 * @return Handle whose @c ref is NULL on failure: KE_ERROR_INVALID_ARGUMENT for a NULL inner target
 *         or params, KE_ERROR_NOT_FOUND when RenderDoc is not loaded into the process.
 */
KE_GPU_RENDER_TARGET_RENDERDOC_API ke_gpu_render_target_handle
ke_gpu_render_target_renderdoc_create(ke_gpu_render_target *inner,
                                      const ke_gpu_render_target_renderdoc_params *params,
                                      ke_error **out_error);

#ifdef __cplusplus
}
#endif

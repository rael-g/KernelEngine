#ifndef KERNEL_ENGINE_RENDER_TEXTURE_TARGET_GPU_RENDER_TARGET_TEXTURE_CREATE_H_
#define KERNEL_ENGINE_RENDER_TEXTURE_TARGET_GPU_RENDER_TARGET_TEXTURE_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_render_target.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_GPU_RENDER_TARGET_TEXTURE_EXPORT
        #define KE_GPU_RENDER_TARGET_TEXTURE_API __declspec(dllexport)
    #elif defined(KE_GPU_RENDER_TARGET_TEXTURE_STATIC)
        #define KE_GPU_RENDER_TARGET_TEXTURE_API
    #else
        #define KE_GPU_RENDER_TARGET_TEXTURE_API __declspec(dllimport)
    #endif
#else
    #define KE_GPU_RENDER_TARGET_TEXTURE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

/// The texture a render target draws into, as the caller created it.
typedef struct ke_gpu_render_target_texture_params
{
    /// Borrowed, must outlive the target; created with KE_GPU_TEXTURE_USAGE_COLOR_ATTACH.
    ke_gpu_texture        texture;
    uint32_t              width;
    uint32_t              height;
    ke_gpu_texture_format format;
} ke_gpu_render_target_texture_params;

/**
 * @brief Creates a render target whose every frame draws into a texture the caller owns, so the
 *        caller reads the frame back from that texture once it was presented.
 * @param device Borrowed, must outlive the target.
 * @return KE_OK, or on failure: KE_RESULT_INVALID_ARGUMENT for a NULL device or
 *         params, an invalid texture or format, or a zero width or height.
 * @param out_target [out] Receives the handle; left zeroed on failure.
 */
KE_GPU_RENDER_TARGET_TEXTURE_API ke_result
ke_gpu_render_target_texture_create(ke_gpu_device *device,
                                    const ke_gpu_render_target_texture_params *params,
                                    ke_gpu_render_target_handle *out_target);

#ifdef __cplusplus
}
#endif

#endif

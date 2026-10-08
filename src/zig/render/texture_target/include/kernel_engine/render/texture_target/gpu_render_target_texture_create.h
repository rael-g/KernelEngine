#pragma once

#include <kernel_engine/common/error.h>
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
 * @return Handle whose @c ref is NULL on failure: KE_ERROR_INVALID_ARGUMENT for a NULL device or
 *         params, an invalid texture or format, or a zero width or height.
 */
KE_GPU_RENDER_TARGET_TEXTURE_API ke_gpu_render_target_handle
ke_gpu_render_target_texture_create(ke_gpu_device *device,
                                    const ke_gpu_render_target_texture_params *params,
                                    ke_error **out_error);

#ifdef __cplusplus
}
#endif

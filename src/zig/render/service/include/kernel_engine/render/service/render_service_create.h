#ifndef KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_CREATE_H_

#include <kernel_engine/math/math.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/io/io.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_render_target.h>
#include <kernel_engine/render/service/render_service.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_CORE_EXPORT
        #define KE_RENDER_CORE_API __declspec(dllexport)
    #elif defined(KE_RENDER_CORE_STATIC)
        #define KE_RENDER_CORE_API
    #else
        #define KE_RENDER_CORE_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_CORE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

/// [bag] The values a render service is created with, each applied as given.
typedef struct ke_render_service_config
{
    /// [utf8] Directory the shaders are loaded from; copied. Required.
    const char           *shader_dir;
    /// Format of the frame's color up to
    /// KE_RENDER_STAGE_HDR_POST.
    ke_gpu_texture_format color_format;
    /// Format of the frame's depth.
    ke_gpu_texture_format depth_format;
    /// Color the frame is cleared to.
    ke_vec4               clear_color;
} ke_render_service_config;


/**
 * @brief Creates a render service whose frames draw into @p target.
 * @param device Borrowed, must outlive the service.
 * @param target Borrowed, must outlive the service; every frame acquires and presents it.
 * @param ecs Borrowed, must outlive the service.
 * @param io [provider] Borrowed, must outlive the service; the shaders are read through it.
 * @param binder Borrowed, must outlive the service; it holds the service's materials and is given
 *        the parameters every shader shares.
 * @param config [borrowed] The service's values, applied as given.
 * @param out_service [out] Receives the handle; left zeroed on failure.
 * @return KE_OK, or on failure; KE_RESULT_INVALID_ARGUMENT when @p device, @p target, @p ecs,
 *         @p io, @p binder, @p config or its shader_dir is NULL, or a format is
 *         KE_GPU_TEXTURE_FORMAT_INVALID.
 */
KE_RENDER_CORE_API ke_result
ke_render_service_create(ke_gpu_device *device, ke_gpu_render_target *target, ke_ecs *ecs, ke_io *io,
                         ke_render_resource_binder *binder, const ke_render_service_config *config,
                         ke_render_service_handle *out_service);

#ifdef __cplusplus
}
#endif

#endif

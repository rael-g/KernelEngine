#ifndef KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_CREATE_H_

#include <kernel_engine/configuration/configuration.h>
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

/// [bag]
typedef struct ke_render_service_params
{
    ke_gpu_device             *device; ///< Borrowed, must outlive the service.
    /// Borrowed, must outlive the service; every frame acquires and presents it.
    ke_gpu_render_target      *target;
    ke_ecs                    *ecs;    ///< Borrowed, must outlive the service.
    /// [utf8] Directory the shaders are loaded from; copied.
    const char                *shader_dir;
    /// [provider] Borrowed, must outlive the service; the shaders are read through it.
    ke_io                     *io;
    /// Borrowed, must outlive the service; it holds the service's materials and is given the
    /// parameters every shader shares.
    ke_render_resource_binder *binder;
    /// Format of the frame's color up to KE_RENDER_STAGE_HDR_POST; zero selects RGBA16_FLOAT.
    ke_gpu_texture_format      color_format;
    /// Format of the frame's depth; zero selects D32_FLOAT.
    ke_gpu_texture_format      depth_format;
    /// Color the frame is cleared to; all four components zero read [render] clear_color_r/g/b/a
    /// from @p configuration, and a key that is absent takes 0.10, 0.15, 0.30, 1.0.
    ke_vec4                    clear_color;
    ke_configuration          *configuration; ///< [optional] Borrowed for the call only.
} ke_render_service_params;

/**
 * @brief Creates a render service whose frames draw into the params' target.
 * @return KE_OK, or on failure; KE_RESULT_INVALID_ARGUMENT when @p params, its
 *         device, target, ecs, shader_dir, io or binder is NULL.
 * @param out_service [out] Receives the handle; left zeroed on failure.
 */
KE_RENDER_CORE_API ke_result
ke_render_service_create(const ke_render_service_params *params, ke_render_service_handle *out_service);

#ifdef __cplusplus
}
#endif

#endif

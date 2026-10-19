#ifndef KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_CREATE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ke_ecs.h>
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

typedef struct ke_render_service_params
{
    ke_gpu_device             *device; ///< Borrowed, must outlive the service.
    /// Borrowed, must outlive the service; every frame acquires and presents it.
    ke_gpu_render_target      *target;
    ke_ecs                    *ecs;    ///< Borrowed, must outlive the service.
    /// [utf8] Directory the shaders are loaded from; copied.
    const char                *shader_dir;
    /// Borrowed, must outlive the service; it holds the service's materials and is given the
    /// parameters every shader shares.
    ke_render_resource_binder *binder;
    /// Format of the frame's color up to KE_RENDER_STAGE_HDR_POST; zero selects RGBA16_FLOAT.
    ke_gpu_texture_format      color_format;
    /// Format of the frame's depth; zero selects D32_FLOAT.
    ke_gpu_texture_format      depth_format;
} ke_render_service_params;

/**
 * @brief Creates a render service whose frames draw into the params' target.
 * @return Handle whose @c ref is NULL on failure; KE_ERROR_INVALID_ARGUMENT when @p params, its
 *         device, target, ecs, shader_dir or binder is NULL.
 */
KE_RENDER_CORE_API ke_render_service_handle
ke_render_service_create(const ke_render_service_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif

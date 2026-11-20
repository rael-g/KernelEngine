#ifndef KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_CREATE_H_

#include <kernel_engine/math/math.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/io/io.h>
#include <kernel_engine/configuration/settings.h>
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

/**
 * @brief Creates a render service whose frames draw into @p target.
 * @param device Borrowed, must outlive the service.
 * @param target Borrowed, must outlive the service; every frame acquires and presents it.
 * @param io [provider] Borrowed, must outlive the service; the shaders are read through it.
 * @param binder Borrowed, must outlive the service; it holds the service's materials and is given
 *        the parameters every shader shares.
 * @param settings [borrowed] Read once. `shader_dir`, a string, default "shaders": the directory,
 *        under the root of the io's file system, the shaders are loaded from.
 * @param out_service [out] Receives the handle; left zeroed on failure.
 * @return KE_OK, or on failure; KE_RESULT_INVALID_ARGUMENT when @p device, @p target,
 *         @p io, @p binder or @p settings is NULL or a setting is refused.
 */
KE_RENDER_CORE_API ke_result
ke_render_service_create(ke_gpu_device *device, ke_gpu_render_target *target, ke_io *io,
                         ke_render_resource_binder *binder, ke_settings *settings,
                         ke_render_service_handle *out_service);

#ifdef __cplusplus
}
#endif

#endif

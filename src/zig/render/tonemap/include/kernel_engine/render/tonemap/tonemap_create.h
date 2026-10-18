#ifndef KERNEL_ENGINE_RENDER_TONEMAP_TONEMAP_CREATE_H_
#define KERNEL_ENGINE_RENDER_TONEMAP_TONEMAP_CREATE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_TONEMAP_EXPORT
        #define KE_RENDER_TONEMAP_API __declspec(dllexport)
    #elif defined(KE_RENDER_TONEMAP_STATIC)
        #define KE_RENDER_TONEMAP_API
    #else
        #define KE_RENDER_TONEMAP_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_TONEMAP_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_render_tonemap ke_render_tonemap;

    typedef struct ke_render_tonemap_handle
    {
        ke_render_tonemap *ref;
        void (*destroy)(ke_render_tonemap *self);
    } ke_render_tonemap_handle;

    /// What the tonemap pass draws from and into. The names are copied.
    typedef struct ke_render_tonemap_params
    {
        ke_runtime        *runtime; ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service; ///< Holds the resources it reads and writes; borrowed.
        ke_gpu_device     *device;  ///< Borrowed.
        ke_logger         *logger;  ///< Optional, borrowed.
        /// [utf8] The HDR resource it reads.
        const char *input;
        /// [utf8] The resource it writes. When the service has none of that name, the pass
        /// declares one the size of the backbuffer in `output_format`.
        const char *output;
        /// Format of a declared `output`; zero selects the backbuffer's.
        ke_gpu_texture_format output_format;
    } ke_render_tonemap_params;

    /// Registers the pass's render-phase system. A missing runtime, service, device, input or
    /// output fails as an invalid argument; the handle's ref is NULL on failure.
    KE_RENDER_TONEMAP_API ke_render_tonemap_handle ke_render_tonemap_create(
        const ke_render_tonemap_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif

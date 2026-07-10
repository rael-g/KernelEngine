#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/core/render_core.h>
#include <kernel_engine/render/gpu_device.h>
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

    // Opaque — nothing outside this plugin calls into it; it registers its own
    // render.tonemap system into `runtime` at create time and does its work
    // through the borrowed ke_render_core (reads "hdr", writes "backbuffer").
    typedef struct ke_render_tonemap ke_render_tonemap;

    typedef struct ke_render_tonemap_handle
    {
        ke_render_tonemap *ref;
        void (*destroy)(ke_render_tonemap *self);
    } ke_render_tonemap_handle;

    // Creates the ACES tonemap pass and registers it as a runtime system.
    // `runtime`, `core`, `device`, `logger` are borrowed (see ke_world for the
    // precedent: a plugin storing only public handles, never another plugin's
    // private state). Handle's ref is NULL on failure.
    KE_RENDER_TONEMAP_API ke_render_tonemap_handle ke_render_tonemap_create(
        ke_runtime *runtime, ke_render_core *core, ke_gpu_device *device,
        ke_logger *logger, ke_error **out_error);

#ifdef __cplusplus
}
#endif

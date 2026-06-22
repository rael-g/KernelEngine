#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/core/render_core.h>

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

// Creates the render core over a borrowed device + ECS. The device records GPU
// work; the ECS mints the resource tag-cids (so the runtime that shares this
// ke_ecs orders the passes). Both are borrowed — caller keeps ownership and
// must outlive the core. Handle's ref is NULL on failure.
KE_RENDER_CORE_API ke_render_core_handle
ke_render_core_create(ke_gpu_device *device, ke_ecs *ecs, ke_error **out_error);

#ifdef __cplusplus
}
#endif

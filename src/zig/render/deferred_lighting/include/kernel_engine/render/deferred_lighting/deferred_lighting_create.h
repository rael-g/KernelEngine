#ifndef KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_DEFERRED_LIGHTING_CREATE_H_
#define KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_DEFERRED_LIGHTING_CREATE_H_

#include <kernel_engine/common/error.h>
#include <stdbool.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_DEFERRED_LIGHTING_EXPORT
        #define KE_RENDER_DEFERRED_LIGHTING_API __declspec(dllexport)
    #elif defined(KE_RENDER_DEFERRED_LIGHTING_STATIC)
        #define KE_RENDER_DEFERRED_LIGHTING_API
    #else
        #define KE_RENDER_DEFERRED_LIGHTING_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_DEFERRED_LIGHTING_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_render_deferred_lighting ke_render_deferred_lighting;

    typedef struct ke_render_deferred_lighting_handle
    {
        ke_render_deferred_lighting *ref;
        void (*destroy)(ke_render_deferred_lighting *self);
    } ke_render_deferred_lighting_handle;

    /// What the deferred lighting pass reads. It joins the chain at KE_RENDER_STAGE_OPAQUE and draws
    /// over the frame's color, sampling the frame's depth. The names are copied.
    typedef struct ke_render_deferred_lighting_params
    {
        ke_runtime        *runtime; ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service; ///< Holds the resources it reads and writes; borrowed.
        ke_gpu_device     *device;  ///< Borrowed.
        ke_logger         *logger;  ///< Optional, borrowed.
        bool               ibl_enabled;
        ke_component_id    camera_cid;
        ke_component_id    world_transform_cid;
        ke_component_id    skybox_cid;
        ke_component_id    frame_cid;
        /// [utf8] The gbuffer group it lights.
        const char *gbuffer;
        /// [utf8] Optional shadow group; without one the shadow is the neutral one.
        const char *shadow;
        /// [utf8] Optional cluster group; without one no clustered light is bound.
        const char *clusters;
    } ke_render_deferred_lighting_params;

    /// Registers the pass's render-phase system. A missing runtime, service, device or
    /// gbuffer fails as an invalid argument; the handle's ref is NULL on failure.
    KE_RENDER_DEFERRED_LIGHTING_API ke_render_deferred_lighting_handle ke_render_deferred_lighting_create(
        const ke_render_deferred_lighting_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif

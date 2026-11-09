#ifndef KERNEL_ENGINE_RENDER_CONTEXT_H_
#define KERNEL_ENGINE_RENDER_CONTEXT_H_

#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/view/view_space.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// The parts every render pass is built on, filled once by the host and handed to each pass's
    /// factory, which reads it during the call. Every pointer is borrowed and must outlive the
    /// passes created with it.
    typedef struct ke_render_context
    {
        ke_runtime              *runtime;    ///< Registers the passes' systems.
        ke_ecs                  *ecs;        ///< Registers the components the passes own.
        ke_render_service       *service;    ///< Holds the resources the passes read and write.
        ke_gpu_device           *device;     ///< Creates the passes' GPU objects.
        ke_view_space           *view_space; ///< Builds views and projections.
        ke_render_camera        *camera;     ///< Answers the camera's matrices.
        ke_render_scene_resolve *scene;      ///< Names the components the passes read.
        ke_render_frame         *frame;      ///< The passes run inside its frame.
    } ke_render_context;

#ifdef __cplusplus
}
#endif

#endif

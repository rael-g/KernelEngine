#ifndef KERNEL_ENGINE_RENDER_CONTEXT_H_
#define KERNEL_ENGINE_RENDER_CONTEXT_H_

#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/extraction/extraction.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/view/view_space.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_render_context
    {
        ke_ecs                  *ecs;        ///< The render world: holds what the passes read and own.
        ke_ecs                  *main;       ///< The main world, whose components are extracted into ecs.
        ke_extraction           *extraction; ///< Copies the main world's components into ecs.
        ke_render_service       *service;    ///< Holds the assets the passes draw.
        ke_gpu_device           *device;     ///< Creates the passes' GPU objects.
        ke_view_space           *view_space; ///< Builds views and projections.
        ke_render_camera        *camera;     ///< Answers the camera's matrices.
        ke_render_scene_resolve *scene;      ///< Names the components the passes read.
        ke_render_frame         *frame;      ///< The frame the passes declare into.
    } ke_render_context;

#ifdef __cplusplus
}
#endif

#endif

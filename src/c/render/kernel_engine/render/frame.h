#ifndef KERNEL_ENGINE_RENDER_FRAME_H_
#define KERNEL_ENGINE_RENDER_FRAME_H_

#include <kernel_engine/ecs/ecs.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** [interface] The systems that begin and end a frame on the render service. */
    typedef struct ke_render_frame
    {
        void *handle;

        /**
         * The tag the system that begins the frame writes and the system that ends it reads. A
         * pass that reads it runs inside the frame.
         */
        ke_component_id (*frame_cid)(struct ke_render_frame *self);
    } ke_render_frame;

    /// [owner]
    typedef struct ke_render_frame_handle
    {
        ke_render_frame *ref;
        void (*destroy)(ke_render_frame *self);
    } ke_render_frame_handle;

#ifdef __cplusplus
}
#endif

#endif

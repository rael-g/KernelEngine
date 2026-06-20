#ifndef KERNEL_ENGINE_THREADING_FRAME_SYNC_H_
#define KERNEL_ENGINE_THREADING_FRAME_SYNC_H_

#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/render/frame_packet.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Double/triple-buffered frame packet handoff — vtable style.
    typedef struct ke_frame_sync
    {
        void *handle;

        ke_frame_packet *(*begin_write)(struct ke_frame_sync *self);
        void             (*end_write)(struct ke_frame_sync *self);

        ke_frame_packet *(*begin_read)(struct ke_frame_sync *self);
        void             (*end_read)(struct ke_frame_sync *self);
    } ke_frame_sync;

    typedef struct ke_frame_sync_handle
    {
        ke_frame_sync *ref;
        void (*destroy)(ke_frame_sync *self);
    } ke_frame_sync_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_THREADING_FRAME_SYNC_H_

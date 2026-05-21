#ifndef KERNEL_ENGINE_KERNEL_THREADING_FRAME_SYNC_H_
#define KERNEL_ENGINE_KERNEL_THREADING_FRAME_SYNC_H_

#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Double/triple-buffered frame packet handoff — vtable style.
    typedef struct ke_frame_sync
    {
        void *handle;
        void (*destroy)(struct ke_frame_sync *self, ke_allocator *alloc);

        /// Sim thread: acquire a writable packet. Blocks if no free slot.
        ke_frame_packet *(*begin_write)(struct ke_frame_sync *self);
        /// Sim thread: release the written packet to the render thread.
        void (*end_write)(struct ke_frame_sync *self);

        /// Render thread: acquire the next ready packet. Blocks until sim signals.
        ke_frame_packet *(*begin_read)(struct ke_frame_sync *self);
        /// Render thread: release the read packet back to the sim thread.
        void (*end_read)(struct ke_frame_sync *self);
    } ke_frame_sync;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_THREADING_FRAME_SYNC_H_

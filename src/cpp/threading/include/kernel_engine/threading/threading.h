#pragma once

// Plugin public C ABI: the only remaining contract is the frame-sync ring buffer
// (sim↔render handoff). Thread spawning and semaphores were removed when their
// vtables were judged to be thin wrappers of stdlib — host languages spawn their
// own threads and use their own sync primitives, with cross-language thread
// identity flowing through ke_thread_set_current_name in the C kernel.

#include <kernel_engine/threading/frame_sync.h>
#include <kernel_engine/threading/threading_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Creates a frame sync ring buffer, filling the @c ke_frame_sync vtable.
    /// @return Handle whose @c ref is NULL on failure.
    KE_THREADING_API ke_frame_sync_handle ke_frame_sync_std_create(uint32_t        buffer_count,
                                                                   uint32_t        draw_capacity,
                                                                   uint32_t        point_capacity,
                                                                   uint32_t        spot_capacity,
                                                                   ke_error      **out_error);

#ifdef __cplusplus
}
#endif

#pragma once

// Plugin public C ABI: one header per plugin, exposing the create entry points
// for each threading primitive (thread, semaphore, frame-sync). The vtable
// abstractions themselves live in the kernel C headers.

#include <kernel_engine/kernel/threading/frame_sync.h>
#include <kernel_engine/kernel/threading/semaphore.h>
#include <kernel_engine/kernel/threading/thread.h>
#include <kernel_engine/threading/threading_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Creates an OS thread, filling the @c ke_thread vtable.
    KE_THREADING_API ke_result ke_thread_std_create(ke_allocator           *alloc,
                                                    const ke_thread_params *desc,
                                                    ke_thread             **out);

    /// @brief Creates a counting semaphore with an initial count, filling the @c ke_semaphore vtable.
    KE_THREADING_API ke_result ke_semaphore_std_create(ke_allocator  *alloc,
                                                       uint32_t       initial,
                                                       ke_semaphore **out);

    /// @brief Creates a frame sync ring buffer, filling the @c ke_frame_sync vtable.
    KE_THREADING_API ke_result ke_frame_sync_std_create(ke_allocator   *alloc,
                                                        uint32_t        buffer_count,
                                                        uint32_t        draw_capacity,
                                                        uint32_t        point_capacity,
                                                        uint32_t        spot_capacity,
                                                        ke_frame_sync **out);

#ifdef __cplusplus
}
#endif

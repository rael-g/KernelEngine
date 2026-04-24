#pragma once

#include <kernel_engine/kernel/threading/frame_sync.h>
#include <kernel_engine/threading/threading_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Creates a frame sync ring buffer, filling the ke_frame_sync vtable.
    KE_THREADING_API ke_result ke_frame_sync_std_create(ke_allocator  *alloc,
                                                         uint32_t       buffer_count,
                                                         uint32_t       draw_capacity,
                                                         uint32_t       point_capacity,
                                                         uint32_t       spot_capacity,
                                                         ke_frame_sync **out);

#ifdef __cplusplus
}
#endif

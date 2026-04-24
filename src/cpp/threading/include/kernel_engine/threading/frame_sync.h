#pragma once

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include <kernel_engine/threading/threading_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_frame_sync ke_frame_sync;

    /// @brief Creates a frame sync object managing a ring of @p buffer_count packets.
    ///        Each packet pre-allocates arrays for draw_commands, point_lights, and spot_lights.
    /// @param alloc             Allocator used for all internal memory.
    /// @param buffer_count      Number of buffered packets (2 = double-buffer, 3 = triple-buffer).
    /// @param draw_capacity     Pre-allocated slots per draw_commands array.
    /// @param point_capacity    Pre-allocated slots per point_lights array.
    /// @param spot_capacity     Pre-allocated slots per spot_lights array.
    /// @param out               Receives the created frame sync on success.
    KE_THREADING_API ke_result ke_frame_sync_create(ke_allocator  *alloc,
                                                     uint32_t       buffer_count,
                                                     uint32_t       draw_capacity,
                                                     uint32_t       point_capacity,
                                                     uint32_t       spot_capacity,
                                                     ke_frame_sync **out);

    /// @brief Acquires a writable packet from the ring (sim thread).
    ///        Blocks if no free buffer is available (render thread is too slow).
    ///        Caller must reset counts before writing: packet->draw_count = 0; etc.
    KE_THREADING_API ke_frame_packet *ke_frame_sync_begin_write(ke_frame_sync *fs);

    /// @brief Releases the written packet to the render thread.
    KE_THREADING_API void ke_frame_sync_end_write(ke_frame_sync *fs);

    /// @brief Acquires the next readable packet (render thread). Blocks until sim signals.
    KE_THREADING_API ke_frame_packet *ke_frame_sync_begin_read(ke_frame_sync *fs);

    /// @brief Releases the read packet back to the sim thread.
    KE_THREADING_API void ke_frame_sync_end_read(ke_frame_sync *fs);

    /// @brief Destroys the frame sync and frees all memory.
    KE_THREADING_API void ke_frame_sync_destroy(ke_frame_sync *fs, ke_allocator *alloc);

#ifdef __cplusplus
}
#endif

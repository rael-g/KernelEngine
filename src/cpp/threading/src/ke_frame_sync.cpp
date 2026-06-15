#include "ke_frame_sync.hpp"
#include <kernel_engine/threading/threading.h>
#include <kernel_engine/threading/frame_sync.h>

#include <cstring>
#include <new>

namespace kernel_engine::threading
{

KeFrameSync::KeFrameSync(ke_allocator *alloc,
                          uint32_t      buffer_count,
                          uint32_t      draw_capacity,
                          uint32_t      point_capacity,
                          uint32_t      spot_capacity)
    : alloc_(alloc)
    , count_(buffer_count)
    , write_sem_(buffer_count)  // all slots free initially
    , read_sem_(0)              // no ready slots
{
    packets_ = static_cast<ke_frame_packet *>(
        alloc->alloc(alloc, sizeof(ke_frame_packet) * buffer_count,
                     alignof(ke_frame_packet)));

    for (uint32_t i = 0; i < buffer_count; ++i)
    {
        auto &p = packets_[i];
        memset(&p, 0, sizeof(ke_frame_packet));
        p.skybox_handle = KE_TEXTURE_NONE;
        p.shadow.map_handle = KE_SHADOW_MAP_NONE;

        p.draw_commands = static_cast<ke_draw_command *>(
            alloc->alloc(alloc, sizeof(ke_draw_command) * draw_capacity,
                         alignof(ke_draw_command)));
        p.draw_capacity = draw_capacity;

        // Shadow draws reuse the same capacity for simplicity
        p.shadow_draw_commands = static_cast<ke_draw_command *>(
            alloc->alloc(alloc, sizeof(ke_draw_command) * draw_capacity,
                         alignof(ke_draw_command)));
        p.shadow_draw_capacity = draw_capacity;

        p.point_lights = static_cast<ke_point_light *>(
            alloc->alloc(alloc, sizeof(ke_point_light) * point_capacity,
                         alignof(ke_point_light)));
        p.point_light_capacity = point_capacity;

        p.spot_lights = static_cast<ke_spot_light *>(
            alloc->alloc(alloc, sizeof(ke_spot_light) * spot_capacity,
                         alignof(ke_spot_light)));
        p.spot_light_capacity = spot_capacity;

        // UI draws: fixed default for now (256 quads/frame — fits Pong's score + instructions
        // with room to spare). When a real game pushes past it we add a parameter or grow on demand.
        constexpr uint32_t kUiDefaultCapacity = 256;
        p.ui_draw_commands = static_cast<ke_ui_draw_command *>(
            alloc->alloc(alloc, sizeof(ke_ui_draw_command) * kUiDefaultCapacity,
                         alignof(ke_ui_draw_command)));
        p.ui_draw_capacity = kUiDefaultCapacity;
    }
}

KeFrameSync::~KeFrameSync()
{
    for (uint32_t i = 0; i < count_; ++i)
    {
        alloc_->free(alloc_, packets_[i].draw_commands);
        alloc_->free(alloc_, packets_[i].shadow_draw_commands);
        alloc_->free(alloc_, packets_[i].point_lights);
        alloc_->free(alloc_, packets_[i].spot_lights);
        alloc_->free(alloc_, packets_[i].ui_draw_commands);
    }
    alloc_->free(alloc_, packets_);
}

void KeFrameSync::semaphore_wait(std::mutex &mtx, std::condition_variable &cv, uint32_t &count)
{
    std::unique_lock<std::mutex> lock(mtx);
    cv.wait(lock, [&count] { return count > 0; });
    --count;
}

void KeFrameSync::semaphore_signal(std::mutex &mtx, std::condition_variable &cv, uint32_t &count)
{
    { std::lock_guard<std::mutex> lock(mtx); ++count; }
    cv.notify_one();
}

ke_frame_packet *KeFrameSync::BeginWrite()
{
    semaphore_wait(write_mtx_, write_cv_, write_sem_);
    auto &p = packets_[write_index_];
    p.draw_count        = 0;
    p.shadow_draw_count = 0;
    p.point_light_count = 0;
    p.spot_light_count  = 0;
    p.ui_draw_count     = 0;
    p.has_dir_light     = false;
    p.has_skybox        = false;
    p.skybox_handle     = KE_TEXTURE_NONE;
    p.shadow.map_handle = KE_SHADOW_MAP_NONE;
    return &p;
}

void KeFrameSync::EndWrite()
{
    write_index_ = (write_index_ + 1) % count_;
    semaphore_signal(read_mtx_, read_cv_, read_sem_);
}

ke_frame_packet *KeFrameSync::BeginRead()
{
    semaphore_wait(read_mtx_, read_cv_, read_sem_);
    return &packets_[read_index_];
}

void KeFrameSync::EndRead()
{
    read_index_ = (read_index_ + 1) % count_;
    semaphore_signal(write_mtx_, write_cv_, write_sem_);
}

} // namespace kernel_engine::threading

// ── C API ────────────────────────────────────────────────────────────────────

namespace
{

struct KeFrameSyncHandle
{
    ke_frame_sync                            vtable; // MUST be first
    kernel_engine::threading::KeFrameSync  *impl;
};

} // namespace

extern "C"
{
    ke_result ke_frame_sync_std_create(ke_allocator  *alloc,
                                        uint32_t       buffer_count,
                                        uint32_t       draw_capacity,
                                        uint32_t       point_capacity,
                                        uint32_t       spot_capacity,
                                        ke_frame_sync **out)
    {
        if (!alloc || buffer_count < 2 || !out) return KE_ERROR_INVALID_ARGUMENT;

        auto *h = static_cast<KeFrameSyncHandle *>(
            alloc->alloc(alloc, sizeof(KeFrameSyncHandle), alignof(KeFrameSyncHandle)));
        if (!h) return KE_ERROR_OUT_OF_MEMORY;

        auto *impl_mem = alloc->alloc(
            alloc, sizeof(kernel_engine::threading::KeFrameSync),
            alignof(kernel_engine::threading::KeFrameSync));
        if (!impl_mem) { alloc->free(alloc, h); return KE_ERROR_OUT_OF_MEMORY; }

        h->impl = new (impl_mem) kernel_engine::threading::KeFrameSync(
            alloc, buffer_count, draw_capacity, point_capacity, spot_capacity);
        h->vtable.handle = h;
        h->vtable.begin_write = [](ke_frame_sync *self) -> ke_frame_packet * {
            if (!self) return nullptr;
            return reinterpret_cast<KeFrameSyncHandle *>(self)->impl->BeginWrite();
        };
        h->vtable.end_write = [](ke_frame_sync *self) {
            if (self) reinterpret_cast<KeFrameSyncHandle *>(self)->impl->EndWrite();
        };
        h->vtable.begin_read = [](ke_frame_sync *self) -> ke_frame_packet * {
            if (!self) return nullptr;
            return reinterpret_cast<KeFrameSyncHandle *>(self)->impl->BeginRead();
        };
        h->vtable.end_read = [](ke_frame_sync *self) {
            if (self) reinterpret_cast<KeFrameSyncHandle *>(self)->impl->EndRead();
        };
        h->vtable.destroy = [](ke_frame_sync *self, ke_allocator *a) {
            if (!self || !a) return;
            auto *hh = reinterpret_cast<KeFrameSyncHandle *>(self);
            hh->impl->~KeFrameSync();
            a->free(a, hh->impl);
            a->free(a, hh);
        };
        *out = &h->vtable;
        return KE_OK;
    }
}

#pragma once

#include <kernel_engine/threading/threading.h>
#include <mutex>
#include <condition_variable>
#include <cstdint>

namespace kernel_engine::threading
{

/// @brief Ring buffer of ke_frame_packet with two counting semaphores.
///        write_sem counts free (writable) slots; read_sem counts ready (readable) slots.
class KeFrameSync
{
  public:
    KeFrameSync(uint32_t buffer_count,
                uint32_t draw_capacity,
                uint32_t point_capacity,
                uint32_t spot_capacity);
    ~KeFrameSync();

    KeFrameSync(const KeFrameSync &)            = delete;
    KeFrameSync &operator=(const KeFrameSync &) = delete;

    ke_frame_packet *BeginWrite();
    void             EndWrite();
    ke_frame_packet *BeginRead();
    void             EndRead();

  private:
    void semaphore_wait(std::mutex &mtx, std::condition_variable &cv, uint32_t &count);
    void semaphore_signal(std::mutex &mtx, std::condition_variable &cv, uint32_t &count);

    ke_frame_packet *packets_;   // ring buffer
    uint32_t         count_;

    uint32_t write_index_ = 0;
    uint32_t read_index_  = 0;

    std::mutex              write_mtx_, read_mtx_;
    std::condition_variable write_cv_,  read_cv_;
    uint32_t                write_sem_; // free slots
    uint32_t                read_sem_;  // ready slots
};

} // namespace kernel_engine::threading

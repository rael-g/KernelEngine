#pragma once

#include <kernel_engine/threading/semaphore.h>
#include <mutex>
#include <condition_variable>
#include <cstdint>

namespace kernel_engine::threading
{

class KeSemaphore
{
  public:
    explicit KeSemaphore(uint32_t initial);

    void Signal();
    void Wait();

  private:
    std::mutex              mutex_;
    std::condition_variable cv_;
    uint32_t                count_;
};

} // namespace kernel_engine::threading

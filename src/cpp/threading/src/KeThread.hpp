#pragma once

#include <kernel_engine/threading/thread.h>

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <thread>

namespace kernel_engine::threading
{

/**
 * @brief Cross-platform thread wrapper.
 *
 * Uses std::thread + a heap-allocated JoinState for cooperative timed-join.
 * No platform-specific code lives here — OS thread naming is delegated to the
 * optional ke_dev_platform passed in the descriptor.
 */
class KeThread
{
  public:
    explicit KeThread(const ke_thread_desc *desc);
    ~KeThread();

    KeThread(const KeThread &)            = delete;
    KeThread &operator=(const KeThread &) = delete;

    void Join();
    bool JoinTimeout(uint32_t timeout_ms);

  private:
    struct JoinState
    {
        std::mutex              mu;
        std::condition_variable cv;
        std::atomic<bool>       done{false};
    };

    std::thread                thread_;
    std::shared_ptr<JoinState> state_;
};

} // namespace kernel_engine::threading

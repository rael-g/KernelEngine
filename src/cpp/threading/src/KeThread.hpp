#pragma once

#include <kernel_engine/threading/thread.h>
#include <thread>

namespace kernel_engine::threading
{

class KeThread
{
  public:
    explicit KeThread(const ke_thread_desc *desc);
    ~KeThread();

    KeThread(const KeThread &)            = delete;
    KeThread &operator=(const KeThread &) = delete;

    void Join();

  private:
    std::thread thread_;
};

} // namespace kernel_engine::threading

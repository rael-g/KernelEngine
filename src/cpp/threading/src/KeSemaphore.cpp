#include "KeSemaphore.hpp"
#include <kernel_engine/threading/semaphore.h>

#include <new>

namespace kernel_engine::threading
{

KeSemaphore::KeSemaphore(uint32_t initial) : count_(initial) {}

void KeSemaphore::Signal()
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        ++count_;
    }
    cv_.notify_one();
}

void KeSemaphore::Wait()
{
    std::unique_lock<std::mutex> lock(mutex_);
    cv_.wait(lock, [this] { return count_ > 0; });
    --count_;
}

} // namespace kernel_engine::threading

// ── C API ────────────────────────────────────────────────────────────────────

extern "C"
{
    struct ke_semaphore
    {
        kernel_engine::threading::KeSemaphore *impl;
    };

    ke_result ke_semaphore_create(ke_allocator  *alloc,
                                   uint32_t       initial,
                                   ke_semaphore **out)
    {
        if (!alloc || !out) return KE_ERROR_INVALID_ARGUMENT;

        auto *handle = static_cast<ke_semaphore *>(
            alloc->alloc(alloc, sizeof(ke_semaphore), alignof(ke_semaphore)));
        if (!handle) return KE_ERROR_OUT_OF_MEMORY;

        auto *impl_mem = alloc->alloc(
            alloc, sizeof(kernel_engine::threading::KeSemaphore),
            alignof(kernel_engine::threading::KeSemaphore));
        if (!impl_mem)
        {
            alloc->free(alloc, handle);
            return KE_ERROR_OUT_OF_MEMORY;
        }

        handle->impl = new (impl_mem) kernel_engine::threading::KeSemaphore(initial);
        *out         = handle;
        return KE_OK;
    }

    void ke_semaphore_signal(ke_semaphore *s)
    {
        if (s && s->impl) s->impl->Signal();
    }

    void ke_semaphore_wait(ke_semaphore *s)
    {
        if (s && s->impl) s->impl->Wait();
    }

    void ke_semaphore_destroy(ke_semaphore *s, ke_allocator *alloc)
    {
        if (!s || !alloc) return;
        if (s->impl)
        {
            s->impl->~KeSemaphore();
            alloc->free(alloc, s->impl);
        }
        alloc->free(alloc, s);
    }
}

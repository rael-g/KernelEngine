#include "KeSemaphore.hpp"
#include <kernel_engine/threading/semaphore.h>
#include <kernel_engine/kernel/threading/semaphore.h>

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

namespace
{

struct KeSemaphoreHandle
{
    ke_semaphore                            vtable; // MUST be first
    kernel_engine::threading::KeSemaphore *impl;
};

} // namespace

extern "C"
{
    ke_result ke_semaphore_std_create(ke_allocator  *alloc,
                                       uint32_t       initial,
                                       ke_semaphore **out)
    {
        if (!alloc || !out) return KE_ERROR_INVALID_ARGUMENT;

        auto *h = static_cast<KeSemaphoreHandle *>(
            alloc->alloc(alloc, sizeof(KeSemaphoreHandle), alignof(KeSemaphoreHandle)));
        if (!h) return KE_ERROR_OUT_OF_MEMORY;

        auto *impl_mem = alloc->alloc(
            alloc, sizeof(kernel_engine::threading::KeSemaphore),
            alignof(kernel_engine::threading::KeSemaphore));
        if (!impl_mem) { alloc->free(alloc, h); return KE_ERROR_OUT_OF_MEMORY; }

        h->impl = new (impl_mem) kernel_engine::threading::KeSemaphore(initial);
        h->vtable.handle = h;
        h->vtable.signal = [](ke_semaphore *self) {
            reinterpret_cast<KeSemaphoreHandle *>(self)->impl->Signal();
        };
        h->vtable.wait = [](ke_semaphore *self) {
            reinterpret_cast<KeSemaphoreHandle *>(self)->impl->Wait();
        };
        h->vtable.destroy = [](ke_semaphore *self, ke_allocator *a) {
            auto *hh = reinterpret_cast<KeSemaphoreHandle *>(self);
            hh->impl->~KeSemaphore();
            a->free(a, hh->impl);
            a->free(a, hh);
        };
        *out = &h->vtable;
        return KE_OK;
    }
}

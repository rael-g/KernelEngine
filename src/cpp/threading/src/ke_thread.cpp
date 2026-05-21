#include "ke_thread.hpp"
#include <kernel_engine/threading/threading.h>
#include <kernel_engine/kernel/threading/thread.h>

#include <cassert>
#include <cstdio>
#include <chrono>
#include <new>
#include <string>

namespace kernel_engine::threading
{

KeThread::KeThread(const ke_thread_params *desc)
    : state_(std::make_shared<JoinState>())
{
    thread_ = std::thread(
        [state         = state_,
         dev_platform  = desc->dev_platform,
         name          = std::string(desc->name ? desc->name : ""),
         func          = desc->func,
         user_data     = desc->user_data]() {
            // 1. Set the TLS name for ke_thread_assert_current.
            ke_thread_set_current_name(name.c_str());

            // 2. Optionally make the name visible to debuggers/profilers.
            if (dev_platform && dev_platform->set_thread_name)
                dev_platform->set_thread_name(dev_platform, name.c_str());

            // 3. Run user code.
            if (func) func(user_data);

            // 4. Signal completion for any waiting JoinTimeout caller.
            {
                std::lock_guard<std::mutex> lk(state->mu);
                state->done = true;
            }
            state->cv.notify_all();
        });
}

KeThread::~KeThread()
{
    if (thread_.joinable())
        thread_.detach();
}

void KeThread::Join()
{
    if (thread_.joinable()) thread_.join();
}

bool KeThread::JoinTimeout(uint32_t timeout_ms)
{
    if (!thread_.joinable()) return true;

    {
        std::unique_lock<std::mutex> lk(state_->mu);
        if (!state_->cv.wait_for(lk, std::chrono::milliseconds(timeout_ms),
                                  [this] { return state_->done.load(); }))
        {
            return false;
        }
    }
    thread_.join();
    return true;
}

} // namespace kernel_engine::threading

// ── C API ────────────────────────────────────────────────────────────────────

namespace
{

struct KeThreadHandle
{
    ke_thread                           vtable; // MUST be first — ke_thread* aliases this
    kernel_engine::threading::KeThread *impl;
};

} // namespace

extern "C"
{
    ke_result ke_thread_std_create(ke_allocator         *alloc,
                                   const ke_thread_params *desc,
                                   ke_thread           **out)
    {
        if (!alloc || !desc || !desc->func || !out) return KE_ERROR_INVALID_ARGUMENT;

        auto *h = static_cast<KeThreadHandle *>(
            alloc->alloc(alloc, sizeof(KeThreadHandle), alignof(KeThreadHandle)));
        if (!h) return KE_ERROR_OUT_OF_MEMORY;

        auto *impl_mem = alloc->alloc(
            alloc, sizeof(kernel_engine::threading::KeThread),
            alignof(kernel_engine::threading::KeThread));
        if (!impl_mem) { alloc->free(alloc, h); return KE_ERROR_OUT_OF_MEMORY; }

        h->impl = new (impl_mem) kernel_engine::threading::KeThread(desc);
        h->vtable.handle = h;
        h->vtable.join = [](ke_thread *self) {
            reinterpret_cast<KeThreadHandle *>(self)->impl->Join();
        };
        h->vtable.join_timeout = [](ke_thread *self, uint32_t timeout_ms) -> ke_bool {
            return reinterpret_cast<KeThreadHandle *>(self)->impl->JoinTimeout(timeout_ms) ? 1 : 0;
        };
        h->vtable.destroy = [](ke_thread *self, ke_allocator *a) {
            auto *hh = reinterpret_cast<KeThreadHandle *>(self);
            hh->impl->~KeThread();
            a->free(a, hh->impl);
            a->free(a, hh);
        };
        *out = &h->vtable;
        return KE_OK;
    }
}

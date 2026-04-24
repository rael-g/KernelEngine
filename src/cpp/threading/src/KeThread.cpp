#include "KeThread.hpp"
#include <kernel_engine/threading/thread.h>
#include <kernel_engine/kernel/threading/thread.h>

#include <cstring>
#include <new>

#if defined(_WIN32)
#    include <windows.h>
#    include <processthreadsapi.h>
#elif defined(__linux__)
#    include <pthread.h>
#elif defined(__APPLE__)
#    include <pthread.h>
#endif

namespace kernel_engine::threading
{

static void set_thread_name_platform(const char *name)
{
    if (!name) return;
#if defined(_WIN32)
    int len = MultiByteToWideChar(CP_UTF8, 0, name, -1, nullptr, 0);
    if (len > 0)
    {
        auto *wname = new wchar_t[len];
        MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, len);
        SetThreadDescription(GetCurrentThread(), wname);
        delete[] wname;
    }
#elif defined(__linux__)
    pthread_setname_np(pthread_self(), name);
#elif defined(__APPLE__)
    pthread_setname_np(name);
#endif
}

KeThread::KeThread(const ke_thread_desc *desc)
    : thread_([desc_copy = *desc]() {
          set_thread_name_platform(desc_copy.name);
          if (desc_copy.affinity_mask != 0)
          {
#if defined(_WIN32)
              SetThreadAffinityMask(GetCurrentThread(), (DWORD_PTR)desc_copy.affinity_mask);
#elif defined(__linux__)
              cpu_set_t cpuset;
              CPU_ZERO(&cpuset);
              for (int i = 0; i < 64; ++i)
                  if (desc_copy.affinity_mask & (1ULL << i))
                      CPU_SET(i, &cpuset);
              pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
#endif
          }
          desc_copy.func(desc_copy.user_data);
      })
{
}

KeThread::~KeThread()
{
    if (thread_.joinable())
        thread_.detach();
}

void KeThread::Join() { thread_.join(); }

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
    ke_result ke_thread_std_create(ke_allocator        *alloc,
                                    const ke_thread_desc *desc,
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
        h->vtable.destroy = [](ke_thread *self, ke_allocator *a) {
            auto *hh = reinterpret_cast<KeThreadHandle *>(self);
            hh->impl->~KeThread();
            a->free(a, hh->impl);
            a->free(a, hh);
        };
        *out = &h->vtable;
        return KE_OK;
    }

    void ke_thread_set_current_name(const char *name)
    {
        kernel_engine::threading::set_thread_name_platform(name);
    }
}

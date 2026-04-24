#include "KeThread.hpp"
#include <kernel_engine/threading/thread.h>

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

extern "C"
{
    struct ke_thread
    {
        kernel_engine::threading::KeThread *impl;
        ke_allocator                        *alloc;
    };

    ke_result ke_thread_create(ke_allocator        *alloc,
                                const ke_thread_desc *desc,
                                ke_thread           **out)
    {
        if (!alloc || !desc || !desc->func || !out) return KE_ERROR_INVALID_ARGUMENT;

        auto *handle = static_cast<ke_thread *>(
            alloc->alloc(alloc, sizeof(ke_thread), alignof(ke_thread)));
        if (!handle) return KE_ERROR_OUT_OF_MEMORY;

        auto *impl_mem = alloc->alloc(
            alloc, sizeof(kernel_engine::threading::KeThread),
            alignof(kernel_engine::threading::KeThread));
        if (!impl_mem)
        {
            alloc->free(alloc, handle);
            return KE_ERROR_OUT_OF_MEMORY;
        }

        handle->impl  = new (impl_mem) kernel_engine::threading::KeThread(desc);
        handle->alloc = alloc;
        *out          = handle;
        return KE_OK;
    }

    void ke_thread_join(ke_thread *t)
    {
        if (t && t->impl) t->impl->Join();
    }

    void ke_thread_destroy(ke_thread *t, ke_allocator *alloc)
    {
        if (!t || !alloc) return;
        if (t->impl)
        {
            t->impl->~KeThread();
            alloc->free(alloc, t->impl);
        }
        alloc->free(alloc, t);
    }

    void ke_thread_set_current_name(const char *name)
    {
        kernel_engine::threading::set_thread_name_platform(name);
    }
}

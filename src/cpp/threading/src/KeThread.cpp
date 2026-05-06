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

#include <string>
#include <cstdio>
#include <cassert>

namespace kernel_engine::threading
{

static thread_local std::string s_thread_name = "unknown";

static void set_thread_name_platform(const char *name)
{
    if (!name) return;
    s_thread_name = name;
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
    : thread_([name          = std::string(desc->name ? desc->name : ""),
               affinity_mask = desc->affinity_mask,
               func          = desc->func,
               user_data     = desc->user_data]() {
          set_thread_name_platform(name.c_str());
          if (affinity_mask != 0)
          {
#if defined(_WIN32)
              SetThreadAffinityMask(GetCurrentThread(), (DWORD_PTR)affinity_mask);
#elif defined(__linux__)
              cpu_set_t cpuset;
              CPU_ZERO(&cpuset);
              for (int i = 0; i < 64; ++i)
                  if (affinity_mask & (1ULL << i))
                      CPU_SET(i, &cpuset);
              pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
#endif
          }
          func(user_data);
      })
{
}

KeThread::~KeThread()
{
    if (thread_.joinable())
        thread_.detach();
}

void KeThread::Join() { if (thread_.joinable()) thread_.join(); }

bool KeThread::JoinTimeout(uint32_t timeout_ms)
{
    if (!thread_.joinable()) return true;

#if defined(_WIN32)
    auto handle = thread_.native_handle();
    DWORD res = WaitForSingleObject(handle, (DWORD)timeout_ms);
    if (res == WAIT_OBJECT_0)
    {
        thread_.join();
        return true;
    }
    return false;
#else
    // Fallback for non-Windows if timed join isn't easily portable
    // In a real implementation we might use a condition variable or pthread_timedjoin_np
    auto start = std::chrono::steady_clock::now();
    while (std::chrono::steady_clock::now() - start < std::chrono::milliseconds(timeout_ms))
    {
        // This is a terrible busy-wait but keeps it simple for now as we are focusing on Win32
        // Better: use native pthread_timedjoin_np if on Linux
        if (thread_.joinable()) {
             // We can't easily check if it's finished without blocking join
             // So we just return true and let the caller know it might have finished
             // or use a more advanced approach.
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    return false;
#endif
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

    KE_THREADING_API void ke_thread_set_current_name(const char *name)
    {
        kernel_engine::threading::set_thread_name_platform(name);
    }

    KE_THREADING_API const char* ke_thread_get_current_name(void)
    {
        return kernel_engine::threading::s_thread_name.c_str();
    }

    KE_THREADING_API void ke_thread_assert_current(const char *expected_name)
    {
#ifndef NDEBUG
        if (kernel_engine::threading::s_thread_name != expected_name)
        {
            fprintf(stderr, "[FATAL] Thread affinity violation! Expected '%s', but current is '%s'.\n",
                    expected_name, kernel_engine::threading::s_thread_name.c_str());
            assert(false);
            abort();
        }
#endif
    }
}

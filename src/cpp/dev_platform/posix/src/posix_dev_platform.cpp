// POSIX implementation of ke_dev_platform (Linux + macOS).

#include <kernel_engine/kernel/dev_platform/dev_platform.h>
#include <kernel_engine/kernel/context/allocator.h>

#include <pthread.h>
#include <new>

#define KE_DEV_PLATFORM_API __attribute__((visibility("default")))

namespace
{

struct PosixDevPlatform
{
    ke_dev_platform vtable;
    ke_allocator   *allocator;
};

void destroy_impl(ke_dev_platform *self)
{
    if (!self || !self->handle) return;
    auto *impl = static_cast<PosixDevPlatform *>(self->handle);
    auto *alloc = impl->allocator;
    impl->~PosixDevPlatform();
    if (alloc) alloc->free(alloc, impl);
}

void set_thread_name_impl(ke_dev_platform * /*self*/, const char *name)
{
    if (!name) return;
#if defined(__APPLE__)
    pthread_setname_np(name);                 // macOS: only current thread
#else
    pthread_setname_np(pthread_self(), name); // Linux: 16-byte limit, silently truncated
#endif
}

} // namespace

extern "C"
{
    KE_DEV_PLATFORM_API ke_result ke_dev_platform_create_posix(
        ke_allocator *alloc, ke_dev_platform **out_platform)
    {
        if (!alloc || !out_platform) return KE_ERROR_INVALID_ARGUMENT;

        auto *impl = static_cast<PosixDevPlatform *>(
            alloc->alloc(alloc, sizeof(PosixDevPlatform), alignof(PosixDevPlatform)));
        if (!impl) return KE_ERROR_OUT_OF_MEMORY;

        new (impl) PosixDevPlatform{};
        impl->allocator = alloc;
        impl->vtable.handle          = impl;
        impl->vtable.destroy         = destroy_impl;
        impl->vtable.set_thread_name = set_thread_name_impl;

        *out_platform = &impl->vtable;
        return KE_OK;
    }
}

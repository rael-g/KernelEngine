// Win32 implementation of ke_dev_platform.
// Currently exposes: SetThreadName via SetThreadDescription (debugger/profiler visibility).

#include <kernel_engine/dev_platform/win32/win32_dev_platform.h>

#include <windows.h>
#include <processthreadsapi.h>

#include <new>

namespace
{

struct Win32DevPlatform
{
    ke_dev_platform vtable;
    ke_allocator   *allocator;
};

void destroy_impl(ke_dev_platform *self)
{
    if (!self || !self->handle) return;
    auto *impl = static_cast<Win32DevPlatform *>(self->handle);
    auto *alloc = impl->allocator;
    impl->~Win32DevPlatform();
    if (alloc) alloc->free(alloc, impl);
}

void set_thread_name_impl(ke_dev_platform * /*self*/, const char *name)
{
    if (!name) return;
    int len = MultiByteToWideChar(CP_UTF8, 0, name, -1, nullptr, 0);
    if (len <= 0) return;
    auto *wname = new wchar_t[len];
    MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, len);
    SetThreadDescription(GetCurrentThread(), wname);
    delete[] wname;
}

} // namespace

extern "C"
{
    KE_DEV_PLATFORM_API ke_result ke_dev_platform_create_win32(
        ke_allocator *alloc, ke_dev_platform **out_platform)
    {
        if (!alloc || !out_platform) return KE_ERROR_INVALID_ARGUMENT;

        auto *impl = static_cast<Win32DevPlatform *>(
            alloc->alloc(alloc, sizeof(Win32DevPlatform), alignof(Win32DevPlatform)));
        if (!impl) return KE_ERROR_OUT_OF_MEMORY;

        new (impl) Win32DevPlatform{};
        impl->allocator = alloc;
        impl->vtable.handle          = impl;
        impl->vtable.destroy         = destroy_impl;
        impl->vtable.set_thread_name = set_thread_name_impl;

        *out_platform = &impl->vtable;
        return KE_OK;
    }
}

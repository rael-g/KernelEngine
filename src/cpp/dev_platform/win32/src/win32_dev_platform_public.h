#ifndef KERNEL_ENGINE_DEV_PLATFORM_WIN32_PUBLIC_H_
#define KERNEL_ENGINE_DEV_PLATFORM_WIN32_PUBLIC_H_

#include <kernel_engine/kernel/dev_platform/dev_platform.h>
#include <kernel_engine/kernel/context/allocator.h>

#ifdef __cplusplus
extern "C"
{
#endif

#if defined(_WIN32)
#  ifdef KE_DEV_PLATFORM_EXPORT
#    define KE_DEV_PLATFORM_API __declspec(dllexport)
#  else
#    define KE_DEV_PLATFORM_API __declspec(dllimport)
#  endif
#else
#  define KE_DEV_PLATFORM_API
#endif

    /**
     * @brief Creates a Win32-backed ke_dev_platform instance.
     * @param alloc        Allocator used for the instance memory.
     * @param out_platform Receives the created platform on success.
     */
    KE_DEV_PLATFORM_API ke_result ke_dev_platform_create_win32(
        ke_allocator *alloc, ke_dev_platform **out_platform);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_DEV_PLATFORM_WIN32_PUBLIC_H_

#ifndef KERNEL_ENGINE_DEV_PLATFORM_WIN32_WIN32_DEV_PLATFORM_H_
#define KERNEL_ENGINE_DEV_PLATFORM_WIN32_WIN32_DEV_PLATFORM_H_

#include <kernel_engine/kernel/dev_platform/dev_platform.h>
#include <kernel_engine/kernel/context/allocator.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_DEV_PLATFORM_API
    #ifdef KE_DEV_PLATFORM_STATIC
        #define KE_DEV_PLATFORM_API
    #else
        #ifdef KE_DEV_PLATFORM_EXPORT
            #define KE_DEV_PLATFORM_API KE_HELPER_EXPORT
        #else
            #define KE_DEV_PLATFORM_API KE_HELPER_IMPORT
        #endif
    #endif
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

#endif // KERNEL_ENGINE_DEV_PLATFORM_WIN32_WIN32_DEV_PLATFORM_H_

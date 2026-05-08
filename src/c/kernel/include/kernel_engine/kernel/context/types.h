#ifndef KERNEL_ENGINE_KERNEL_CONTEXT_TYPES_H_
#define KERNEL_ENGINE_KERNEL_CONTEXT_TYPES_H_

#include <stdbool.h>
#include <stdint.h>
#include <kernel_engine/kernel/common/error.h>

#ifdef __cplusplus
extern "C"
{
#endif

// --- Visibility infrastructure ---
#if defined(_WIN32) || defined(__CYGWIN__)
#define KE_HELPER_EXPORT __declspec(dllexport)
#define KE_HELPER_IMPORT __declspec(dllimport)
#else
#define KE_HELPER_EXPORT __attribute__((visibility("default")))
#define KE_HELPER_IMPORT __attribute__((visibility("default")))
#endif

#ifdef KE_KERNEL_STATIC
#define KE_API
#else
#ifdef KE_KERNEL_EXPORT
#define KE_API KE_HELPER_EXPORT
#else
#define KE_API KE_HELPER_IMPORT
#endif
#endif

// --- Thread Local Storage ---
#if defined(_MSC_VER)
#define KE_THREAD_LOCAL __declspec(thread)
#else
#define KE_THREAD_LOCAL _Thread_local
#endif

    /// @brief Boolean type for stable FFI (exactly 1 byte).
    typedef uint8_t ke_bool;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_CONTEXT_TYPES_H_

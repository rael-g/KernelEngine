#pragma once

#include <stdbool.h>
#include <stdint.h>

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

#ifdef KE_CORE_STATIC
#define KE_API
#else
#ifdef KE_CORE_EXPORT
#define KE_API KE_HELPER_EXPORT
#else
#define KE_API KE_HELPER_IMPORT
#endif
#endif

    /// @brief Handle to the engine instance.
    typedef void *ke_engine_h;

    /// @brief Unique identifier for a system.
    typedef uint64_t ke_system_id;

#ifdef __cplusplus
}
#endif

#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/configuration/configuration.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_CONFIGURATION_EXPORT
        #define KE_CONFIGURATION_API __declspec(dllexport)
    #elif defined(KE_CONFIGURATION_STATIC)
        #define KE_CONFIGURATION_API
    #else
        #define KE_CONFIGURATION_API __declspec(dllimport)
    #endif
#else
    #define KE_CONFIGURATION_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    // Creates an empty settings store. A loader populates it via the set_* slots.
    // Handle's ref is NULL on failure.
    KE_CONFIGURATION_API ke_configuration_handle ke_configuration_create(ke_error **out_error);

#ifdef __cplusplus
}
#endif

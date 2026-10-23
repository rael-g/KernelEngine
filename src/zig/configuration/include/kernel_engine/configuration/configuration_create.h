#ifndef KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_CREATE_H_
#define KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_CREATE_H_

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

    /**
     * Creates an empty configuration store.
     * @param out_store [out] Receives the store; left zeroed on failure.
     * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p out_store, or KE_RESULT_OUT_OF_MEMORY.
     */
    KE_CONFIGURATION_API ke_result ke_configuration_create(ke_configuration_handle *out_store);

#ifdef __cplusplus
}
#endif

#endif

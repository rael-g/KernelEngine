#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/configuration/configuration.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_CONFIGURATION_TOML_EXPORT
        #define KE_CONFIGURATION_TOML_API __declspec(dllexport)
    #elif defined(KE_CONFIGURATION_TOML_STATIC)
        #define KE_CONFIGURATION_TOML_API
    #else
        #define KE_CONFIGURATION_TOML_API __declspec(dllimport)
    #endif
#else
    #define KE_CONFIGURATION_TOML_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    KE_CONFIGURATION_TOML_API bool ke_configuration_toml_load(ke_configuration *cfg,
                                                              const char       *path,
                                                              ke_error        **out_error);

#ifdef __cplusplus
}
#endif

#ifndef KERNEL_ENGINE_CONFIGURATION_TOML_CONFIGURATION_TOML_H_
#define KERNEL_ENGINE_CONFIGURATION_TOML_CONFIGURATION_TOML_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/configuration/configuration_source.h>

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

    /// Creates a configuration source that reads a TOML file: each table becomes a section named
    /// by its path joined with dots, arrays are skipped, and every other key is written as an
    /// integer, a double, a boolean or a string, tried in that order. A parse error writes nothing.
    /// @return Handle whose @c ref is NULL on failure.
    KE_CONFIGURATION_TOML_API ke_configuration_source_handle ke_configuration_toml_create(ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif

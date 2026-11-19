#ifndef KERNEL_ENGINE_CONFIGURATION_TOML_CONFIGURATION_TOML_H_
#define KERNEL_ENGINE_CONFIGURATION_TOML_CONFIGURATION_TOML_H_

#include <kernel_engine/configuration/configuration_source.h>
#include <kernel_engine/file_system/file_system.h>

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

    /// Creates a configuration source that reads a TOML file through @p file_system, synchronously: each table
    /// becomes a section named by its path joined with dots, an array of tables one section per
    /// element named by the array's key and the element's index, an array of values one key per
    /// element named the same way, and every other key is written as an integer, a double, a boolean
    /// or a string, tried in that order. A parse
    /// error writes nothing.
    /// @param file_system [borrowed] The file system it reads through; borrowed for the lifetime of the source.
    /// @param out_source [out] Receives the source; left zeroed on failure.
    /// @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p file_system or @p out_source, or
    ///         KE_RESULT_OUT_OF_MEMORY.
    KE_CONFIGURATION_TOML_API ke_result ke_configuration_toml_create(ke_file_system *file_system, ke_configuration_source_handle *out_source);

#ifdef __cplusplus
}
#endif

#endif

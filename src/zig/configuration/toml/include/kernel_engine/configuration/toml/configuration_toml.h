#ifndef KERNEL_ENGINE_CONFIGURATION_TOML_CONFIGURATION_TOML_H_
#define KERNEL_ENGINE_CONFIGURATION_TOML_CONFIGURATION_TOML_H_

#include <kernel_engine/configuration/configuration_source.h>
#include <kernel_engine/io/io.h>

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

    /** Construction parameters for ke_configuration_toml_create. */
    typedef struct ke_configuration_toml_params
    {
        /// [provider] The io each load reads its file through; required, borrowed for the lifetime
        /// of the source.
        ke_io *io;
    } ke_configuration_toml_params;

    /// Creates a configuration source that reads a TOML file through @p params' io: each table
    /// becomes a section named by its path joined with dots, arrays are skipped, and every other
    /// key is written as an integer, a double, a boolean or a string, tried in that order. A parse
    /// error writes nothing.
    /// @param params [borrowed] The io.
    /// @param out_source [out] Receives the source; left zeroed on failure.
    /// @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p params, io or @p out_source, or
    ///         KE_RESULT_OUT_OF_MEMORY.
    KE_CONFIGURATION_TOML_API ke_result ke_configuration_toml_create(const ke_configuration_toml_params *params,
                                                                     ke_configuration_source_handle *out_source);

#ifdef __cplusplus
}
#endif

#endif

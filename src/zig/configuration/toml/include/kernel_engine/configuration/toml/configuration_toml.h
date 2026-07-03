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

    // Reads the TOML file at `path` and populates `cfg` via its set_* slots:
    // every `[section]` table becomes a section, each scalar key a typed value
    // (dotted sub-tables flatten to dotted section names, e.g. `[a.b]` → "a.b").
    // Arrays and timestamps are skipped for now.
    //
    // A missing file is NOT an error — returns true with `cfg` untouched, so the
    // consumer's defaults apply (chapter 16 §2.4). A parse error or an IO error
    // other than not-found returns false and sets out_error.
    KE_CONFIGURATION_TOML_API bool ke_configuration_toml_load(ke_configuration *cfg,
                                                              const char       *path,
                                                              ke_error        **out_error);

#ifdef __cplusplus
}
#endif

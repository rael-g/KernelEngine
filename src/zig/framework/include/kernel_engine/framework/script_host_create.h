#ifndef KERNEL_ENGINE_FRAMEWORK_SCRIPT_HOST_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCRIPT_HOST_CREATE_H_

#include <kernel_engine/framework/script_host.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_FRAMEWORK_API
#if defined(_WIN32) || defined(__CYGWIN__)
#ifdef KE_FRAMEWORK_STATIC
#define KE_FRAMEWORK_API
#else
#ifdef KE_FRAMEWORK_EXPORT
#define KE_FRAMEWORK_API __declspec(dllexport)
#else
#define KE_FRAMEWORK_API __declspec(dllimport)
#endif
#endif
#else
#define KE_FRAMEWORK_API __attribute__((visibility("default")))
#endif
#endif

    /// Sizing for one script host. Both are workload shapes — how many node types
    /// a game declares and how many of them it spawns — so a default is a
    /// convenience, never a ceiling the engine imposes on a game.
    typedef struct ke_script_host_params
    {
        uint32_t max_types;     ///< Distinct script types; 0 uses the default.
        uint32_t max_instances; ///< Live bindings; 0 uses the default.
    } ke_script_host_params;

    /// Allocates a script host reading the scene graph out of @c ecs, which is what
    /// lets it answer descendant and ancestor lookups without the binding runtime
    /// walking the hierarchy itself. @c params may be NULL to take every default.
    /// @return Handle whose @c ref is NULL on failure.
    KE_FRAMEWORK_API ke_script_host_handle ke_script_host_create(
        ke_ecs                      *ecs,
        const ke_script_host_params *params,
        ke_error                   **out_error);

#ifdef __cplusplus
}
#endif

#endif

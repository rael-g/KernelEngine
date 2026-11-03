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

    /// Sizing for one script host. The defaults are conveniences, not ceilings.
    /// [bag] Instances need no sizing.
    typedef struct ke_script_host_params
    {
        uint32_t max_types; ///< Distinct script types; 0 uses the default.
    } ke_script_host_params;

    /// Allocates a script host that reads the scene graph out of @c ecs.
    /// @c params may be NULL to take every default.
    /// @param out_host [out] Receives the host; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs or @p out_host,
    ///         KE_RESULT_NOT_FOUND when no scene tree registered its components on @p ecs,
    ///         KE_RESULT_OUT_OF_MEMORY, or the ecs's code when it refuses a component.
    KE_FRAMEWORK_API ke_result ke_script_host_create(
        ke_ecs                      *ecs,
        const ke_script_host_params *params,
        ke_script_host_handle       *out_host);

#ifdef __cplusplus
}
#endif

#endif

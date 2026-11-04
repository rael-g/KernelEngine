#ifndef KERNEL_ENGINE_FRAMEWORK_COMPONENT_REGISTRY_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_COMPONENT_REGISTRY_CREATE_H_

#include <kernel_engine/framework/component_registry.h>

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

    /// Creates a component registry over @p ecs, registering the transform, 2D transform and
    /// world transform components on it with their field tables.
    /// @param ecs [borrowed] Resolves the names a scene writes; must outlive the registry.
    /// @param out_registry [out] Receives the registry; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs or @p out_registry,
    ///         KE_RESULT_OUT_OF_MEMORY, or the code of the ecs that refused a component.
    KE_FRAMEWORK_API ke_result ke_component_registry_create(
        ke_ecs *ecs, ke_component_registry_handle *out_registry);

#ifdef __cplusplus
}
#endif

#endif

#ifndef KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_SYSTEMS_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_SYSTEMS_CREATE_H_
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/module/module.h>


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

    /// Creates the module of @p types: attaching it registers the ready and exit behaviours and the
    /// systems that clear the last tick's events in the pre_update schedule's pre_update set, fixed
    /// update behaviours in the fixed schedule's fixed_update set, update behaviours in the update
    /// schedule's update set, and event behaviours and the system that frees the nodes that left the
    /// tree in its post_update set, for every type and event registered before or after. Detaching
    /// removes them all; the types and events stay.
    /// @param types [borrowed] Created by ke_node_types_create; must outlive the module.
    /// @param out_module [out] Receives the module; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument or node types this library did
    ///         not create.
    KE_FRAMEWORK_API ke_result ke_node_types_systems_create(
        ke_node_types    *types,
        ke_module_handle *out_module);
#ifdef __cplusplus
}
#endif

#endif

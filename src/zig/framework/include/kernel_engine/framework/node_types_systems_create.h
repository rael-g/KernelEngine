#ifndef KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_SYSTEMS_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_SYSTEMS_CREATE_H_
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/schedule/schedule.h>


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

    /// Creates the module of @p types: it registers the ready and exit behaviours and the systems
    /// that clear the last tick's events in @p pre_update_set of @p pre_update, fixed update
    /// behaviours in @p fixed_update_set of @p fixed_update, update behaviours in @p update_set of
    /// @p update, and event behaviours and the system that frees the nodes that left the tree in
    /// @p post_update_set of @p post_update, for every type and event registered before or after.
    /// Destroying the module removes them all; the types and events stay.
    /// @param types [borrowed] Created by ke_node_types_create; must outlive the module.
    /// @param pre_update [borrowed] Must outlive the module.
    /// @param pre_update_set The set of @p pre_update the ready, exit and event-clearing systems join.
    /// @param fixed_update [borrowed] Must outlive the module.
    /// @param fixed_update_set The set of @p fixed_update the fixed update behaviours join.
    /// @param update [borrowed] Must outlive the module.
    /// @param update_set The set of @p update the update behaviours join.
    /// @param post_update [borrowed] Must outlive the module.
    /// @param post_update_set The set of @p post_update the event behaviours and the reaping system join.
    /// @param out_module [out] Receives the module; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument or node types this library did
    ///         not create; KE_RESULT_NOT_SUPPORTED while another module of @p types lives; the code a
    ///         schedule refused a system with, nothing left registered.
    KE_FRAMEWORK_API ke_result ke_node_types_systems_create(
        ke_node_types      *types,
        ke_schedule        *pre_update,
        ke_schedule_set_id  pre_update_set,
        ke_schedule        *fixed_update,
        ke_schedule_set_id  fixed_update_set,
        ke_schedule        *update,
        ke_schedule_set_id  update_set,
        ke_schedule        *post_update,
        ke_schedule_set_id  post_update_set,
        ke_owner           *out_module);
#ifdef __cplusplus
}
#endif

#endif

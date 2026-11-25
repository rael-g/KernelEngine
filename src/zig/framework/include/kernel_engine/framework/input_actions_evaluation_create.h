#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_EVALUATION_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_EVALUATION_CREATE_H_

#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/input/input.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/scheduling/schedule.h>

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

    /// Creates the module that evaluates @p actions: it registers the exclusive system
    /// "input.actions" in @p pre_update_set of @p pre_update, which each run advances @p input's
    /// frame and evaluates the maps against its snapshot. Destroying the module unregisters it.
    /// @param actions [borrowed] Created by ke_input_actions_create; must outlive the module.
    /// @param input [borrowed] Must outlive the module.
    /// @param pre_update [borrowed] Must outlive the module.
    /// @param pre_update_set The set of @p pre_update the system joins.
    /// @param out_module [out] Receives the module; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument or actions this library did not
    ///         create; KE_RESULT_OUT_OF_MEMORY; the code the schedule refused the system with.
    KE_FRAMEWORK_API ke_result ke_input_actions_evaluation_create(
        ke_input_actions   *actions,
        ke_input           *input,
        ke_schedule        *pre_update,
        ke_schedule_set_id  pre_update_set,
        ke_owner           *out_module);
#ifdef __cplusplus
}
#endif

#endif

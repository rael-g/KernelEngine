#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_EVALUATION_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_EVALUATION_CREATE_H_

#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/input/input.h>
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

    /// Creates the module that evaluates @p actions each tick: attaching it registers the exclusive
    /// system "input.actions" in the pre_update schedule's pre_update set, which advances @p input's
    /// frame and evaluates the maps against its snapshot.
    /// @param actions [borrowed] Created by ke_input_actions_create; must outlive the module.
    /// @param input [borrowed] Must outlive the module.
    /// @param out_module [out] Receives the module; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument or actions this library did not
    ///         create; KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_input_actions_evaluation_create(
        ke_input_actions *actions,
        ke_input         *input,
        ke_module_handle *out_module);
#ifdef __cplusplus
}
#endif

#endif

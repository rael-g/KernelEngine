#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_

#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/io/io.h>

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

    /// Creates an empty action map.
    /// @param io [borrowed] What load reads its file through; must outlive the map.
    /// @param out_actions [out] Receives the map; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p io or @p out_actions, or
    ///         KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_input_actions_create(
        ke_io                   *io,
        ke_input_actions_handle *out_actions);

#ifdef __cplusplus
}
#endif

#endif

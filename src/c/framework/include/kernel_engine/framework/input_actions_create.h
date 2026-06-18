#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_

#include <kernel_engine/framework/input_actions.h>

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

    KE_FRAMEWORK_API ke_result ke_input_actions_create(
        ke_input_actions_handle *out_actions,
        ke_error         **out_error);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_

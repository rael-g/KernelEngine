#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_

#include <kernel_engine/kernel/framework/input_actions.h>

#ifdef __cplusplus
extern "C"
{
#endif

    KE_FRAMEWORK_API ke_result ke_input_actions_create(
        ke_allocator       *alloc,
        ke_input_actions  **out_actions);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_

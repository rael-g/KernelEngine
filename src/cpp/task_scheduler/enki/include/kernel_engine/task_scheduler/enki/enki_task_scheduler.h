#pragma once

#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/task_scheduler/task_scheduler.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_TASK_SCHEDULER_API
    #ifdef KE_TASK_SCHEDULER_STATIC
        #define KE_TASK_SCHEDULER_API
    #else
        #ifdef KE_TASK_SCHEDULER_EXPORT
            #define KE_TASK_SCHEDULER_API KE_HELPER_EXPORT
        #else
            #define KE_TASK_SCHEDULER_API KE_HELPER_IMPORT
        #endif
    #endif
#endif

/**
 * @brief Creates a task scheduler implementation based on enkiTS.
 */
KE_TASK_SCHEDULER_API ke_result ke_task_scheduler_enki_create(struct ke_allocator *allocator, struct ke_task_scheduler **out_scheduler);

#ifdef __cplusplus
}
#endif

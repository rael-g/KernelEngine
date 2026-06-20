#pragma once

#include <kernel_engine/common/export.h>
#include <kernel_engine/scheduler/scheduler.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_SCHEDULER_API
    #ifdef KE_SCHEDULER_STATIC
        #define KE_SCHEDULER_API
    #else
        #ifdef KE_SCHEDULER_EXPORT
            #define KE_SCHEDULER_API KE_EXPORT
        #else
            #define KE_SCHEDULER_API KE_IMPORT
        #endif
    #endif
#endif

/**
 * @brief Creates a scheduler implementation based on enkiTS.
 * @return Handle whose @c ref is NULL on failure.
 */
KE_SCHEDULER_API ke_scheduler_handle ke_scheduler_enki_create(struct ke_error **out_error);

#ifdef __cplusplus
}
#endif

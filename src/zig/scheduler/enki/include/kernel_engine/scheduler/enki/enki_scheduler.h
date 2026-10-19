#ifndef KERNEL_ENGINE_SCHEDULER_ENKI_ENKI_SCHEDULER_H_
#define KERNEL_ENGINE_SCHEDULER_ENKI_ENKI_SCHEDULER_H_

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

/** Construction parameters for ke_scheduler_enki_create. */
typedef struct ke_scheduler_enki_params
{
    /// Worker threads besides the calling thread. 0 takes one per hardware thread
    /// besides the calling one.
    uint32_t worker_count;
} ke_scheduler_enki_params;

/**
 * @brief Creates a scheduler.
 * @param params [borrowed,optional] Construction parameters; NULL takes every default.
 * @return Handle whose @c ref is NULL on failure.
 */
KE_SCHEDULER_API ke_scheduler_handle ke_scheduler_enki_create(const ke_scheduler_enki_params *params,
                                                              struct ke_error              **out_error);

#ifdef __cplusplus
}
#endif

#endif

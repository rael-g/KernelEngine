#ifndef KERNEL_ENGINE_TASK_POOL_ENKI_ENKI_TASK_POOL_H_
#define KERNEL_ENGINE_TASK_POOL_ENKI_ENKI_TASK_POOL_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/task_pool/task_pool.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_TASK_POOL_API
    #ifdef KE_TASK_POOL_STATIC
        #define KE_TASK_POOL_API
    #else
        #ifdef KE_TASK_POOL_EXPORT
            #define KE_TASK_POOL_API KE_EXPORT
        #else
            #define KE_TASK_POOL_API KE_IMPORT
        #endif
    #endif
#endif

/** [bag] Construction parameters for ke_task_pool_enki_create. */
typedef struct ke_task_pool_enki_params
{
    /// Worker threads besides the calling thread. 0 takes one per hardware thread
    /// besides the calling one.
    uint32_t worker_count;
} ke_task_pool_enki_params;

/**
 * @brief Creates a task pool.
 * @param params [borrowed,optional] Construction parameters; NULL takes every default.
 * @param out_task_pool [out] Receives the task pool; left zeroed on failure.
 * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p out_task_pool, or
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_TASK_POOL_API ke_result ke_task_pool_enki_create(const ke_task_pool_enki_params *params,
                                                    ke_task_pool_handle            *out_task_pool);

#ifdef __cplusplus
}
#endif

#endif

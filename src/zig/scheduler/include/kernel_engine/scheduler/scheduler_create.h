#ifndef KERNEL_ENGINE_SCHEDULER_SCHEDULER_CREATE_H_
#define KERNEL_ENGINE_SCHEDULER_SCHEDULER_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/scheduler/scheduler.h>
#include <kernel_engine/task_pool/task_pool.h>
#include <kernel_engine/ecs/ke_ecs.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_SCHEDULER_CREATE_API
#  ifdef KE_SCHEDULER_CREATE_EXPORT
#    define KE_SCHEDULER_CREATE_API KE_EXPORT
#  else
#    define KE_SCHEDULER_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Creates a scheduler over @p ecs and @p task_pool, both borrowed for its lifetime.
 * @param config [borrowed] Required; every field is read as given.
 * @param out_scheduler [out] Receives the scheduler; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs, @p task_pool, @p config or
 *         @p out_scheduler; KE_RESULT_OUT_OF_MEMORY.
 */
KE_SCHEDULER_CREATE_API ke_result ke_scheduler_create(ke_ecs                    *ecs,
                                                      ke_task_pool              *task_pool,
                                                      const ke_scheduler_config *config,
                                                      ke_scheduler_handle       *out_scheduler);

#ifdef __cplusplus
}
#endif

#endif

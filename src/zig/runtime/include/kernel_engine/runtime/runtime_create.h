#ifndef KERNEL_ENGINE_RUNTIME_RUNTIME_CREATE_H_
#define KERNEL_ENGINE_RUNTIME_RUNTIME_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/task_pool/task_pool.h>
#include <kernel_engine/ecs/ke_ecs.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_RUNTIME_CREATE_API
#  ifdef KE_RUNTIME_CREATE_EXPORT
#    define KE_RUNTIME_CREATE_API KE_EXPORT
#  else
#    define KE_RUNTIME_CREATE_API KE_IMPORT
#  endif
#endif

typedef struct ke_runtime_params {
    /// Timestep KE_PHASE_FIXED_UPDATE runs at, in seconds. 0 selects 1/60.
    float fixed_dt;

    /// Largest catch-up budget a tick may accumulate, in seconds; excess is
    /// discarded. 0 selects 0.25.
    float fixed_dt_max_accum;

    /// Most systems one phase may hold; registering past it fails. 0 selects 256.
    uint32_t max_systems_per_phase;
} ke_runtime_params;

/**
 * Creates a runtime over @p ecs and @p task_pool, both borrowed for its lifetime.
 * @param params [borrowed,optional] NULL takes every default.
 * @param out_runtime [out] Receives the runtime; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs, @p task_pool or @p out_runtime;
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_RUNTIME_CREATE_API ke_result ke_runtime_create(ke_ecs                  *ecs,
                                                  ke_task_pool            *task_pool,
                                                  const ke_runtime_params *params,
                                                  ke_runtime_handle       *out_runtime);

#ifdef __cplusplus
}
#endif

#endif

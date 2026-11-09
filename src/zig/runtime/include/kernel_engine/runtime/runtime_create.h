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

/// [bag]
typedef struct ke_runtime_params {
    /// Timestep KE_PHASE_FIXED_UPDATE runs at, in seconds; greater than zero.
    float fixed_dt;

    /// Largest catch-up budget a tick may accumulate, in seconds; excess is
    /// discarded; greater than zero.
    float fixed_dt_max_accum;

    /// Most systems one phase may hold; registering past it fails.
    uint32_t max_systems_per_phase;
} ke_runtime_params;


/**
 * Creates a runtime over @p ecs and @p task_pool, both borrowed for its lifetime.
 * @param params [borrowed] Required; every field is read as given.
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

#ifndef KERNEL_ENGINE_RUNTIME_RUNTIME_CREATE_H_
#define KERNEL_ENGINE_RUNTIME_RUNTIME_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/scheduler/scheduler.h>
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

    /// Most archetype segments one query may match; a tick whose query matches more fails.
    /// 0 selects 32.
    uint32_t max_segments_per_query;
} ke_runtime_params;

KE_RUNTIME_CREATE_API ke_runtime_handle ke_runtime_create(ke_ecs                  *ecs,
                                                          ke_scheduler            *scheduler,
                                                          const ke_runtime_params *params,
                                                          ke_error               **out_error);

#ifdef __cplusplus
}
#endif

#endif

#ifndef KERNEL_ENGINE_RUNTIME_RUNTIME_CREATE_H_
#define KERNEL_ENGINE_RUNTIME_RUNTIME_CREATE_H_

// ke_runtime_create — the in-house scheduler.
// Owns the system catalog + phase loop + (eventually) parallel wave dispatch.
// Storage is borrowed via ke_ecs*; the scheduler never owns it.

#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/runtime/runtime.h>
#include <kernel_engine/kernel/task_scheduler/task_scheduler.h>
#include <kernel_engine/kernel/ecs/ke_ecs.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_runtime_params {
    // Fixed timestep for KE_PHASE_FIXED_UPDATE. The runtime accumulates real
    // elapsed dt across tick() calls and runs FIXED_UPDATE 0..N times per tick
    // to catch up at this constant rate. Default (when 0) = 1/60s.
    float fixed_dt;

    // Maximum accumulator value to prevent "spiral of death" when frame time
    // exceeds catch-up budget. Default (when 0) = 0.25s — 15 fixed steps at 1/60.
    // Excess dt above this cap is discarded silently.
    float fixed_dt_max_accum;
} ke_runtime_params;

KE_API ke_result ke_runtime_create(ke_allocator            *alloc,
                                    ke_ecs                  *ecs,
                                    ke_task_scheduler       *task_scheduler,
                                    const ke_runtime_params *params,
                                    ke_runtime             **out_runtime);

#ifdef __cplusplus
}
#endif

#endif  // KERNEL_ENGINE_RUNTIME_RUNTIME_CREATE_H_

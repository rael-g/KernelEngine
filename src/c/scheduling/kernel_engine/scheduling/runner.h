#ifndef KERNEL_ENGINE_SCHEDULING_RUNNER_H_
#define KERNEL_ENGINE_SCHEDULING_RUNNER_H_

#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C" {
#endif

/// [interface] The loop of a program: ticks what it was given until its own end comes or the program is asked to
/// end, feeding each tick what the place it runs in produces, as a window's events.
typedef struct ke_runner {
    void *handle;

    /// Runs the loop on the calling thread until it ends.
    /// @return KE_OK when the loop ended; the code a tick failed with, no later tick running.
    ke_result (*run)(struct ke_runner *self);
} ke_runner;

/// [owner]
typedef struct ke_runner_handle {
    ke_runner *ref;
    void (*destroy)(ke_runner *self);
} ke_runner_handle;

#ifdef __cplusplus
}
#endif

#endif

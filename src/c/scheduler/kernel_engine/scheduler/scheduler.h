#ifndef KERNEL_ENGINE_SCHEDULER_SCHEDULER_H_
#define KERNEL_ENGINE_SCHEDULER_SCHEDULER_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/schedule/schedule.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_scheduler ke_scheduler;

/// When a schedule runs within the ticks of a scheduler.
typedef enum ke_scheduler_cadence {
    /// Once per tick, with the tick's dt.
    KE_SCHEDULER_CADENCE_EVERY_TICK = 0,
    /// Once per fixed step, as many steps as the tick's time covers, with the fixed dt. Fixed
    /// schedules added one after another run together, in order, at each step.
    KE_SCHEDULER_CADENCE_FIXED      = 1,
    /// Once, before every other schedule of the first tick, with a dt of zero.
    KE_SCHEDULER_CADENCE_STARTUP    = 2,
    /// Once, when the scheduler shuts down after a tick ran, with a dt of zero.
    KE_SCHEDULER_CADENCE_SHUTDOWN   = 3,
} ke_scheduler_cadence;

/// [interface] The frame loop: runs the schedules it was given, each when its cadence says, tick by
/// tick.
typedef struct ke_scheduler {
    void *handle;

    /// Adds a schedule; a tick runs the schedules in the order they were added.
    /// @param schedule [borrowed] Must outlive the scheduler.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p schedule or an unknown cadence;
    ///         KE_RESULT_NOT_SUPPORTED after shutdown; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*add_schedule)(ke_scheduler *self, ke_schedule *schedule, ke_scheduler_cadence cadence);

    /// Runs the schedules: on the first tick the startup ones first, then each every-tick one, and
    /// each block of fixed ones once per fixed step the accumulated time covers, the accumulation
    /// capped at fixed_dt_max_accum.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a negative @p dt; KE_RESULT_NOT_SUPPORTED after
    ///         shutdown; the code a schedule's run failed with, no later schedule running.
    ke_result (*tick)(ke_scheduler *self, float dt);

    /// Runs the shutdown schedules once if a tick ran; a later call does nothing, and a later tick is
    /// refused. Destroying the scheduler calls it for a caller that did not.
    /// @return KE_OK; the code a schedule's run failed with.
    ke_result (*shutdown)(ke_scheduler *self);

    /// Records that the program should end; any body or the caller may ask, from any thread.
    void (*request_exit)(ke_scheduler *self);

    /// Whether a request to end the program was recorded.
    bool (*exit_requested)(ke_scheduler *self);

    /// The number of the schedule run started last; every run started takes the next number, and
    /// zero means none started. Readable from any thread; a body stamps what it writes with it.
    uint64_t (*sequence)(ke_scheduler *self);

    /// Whether every added schedule that reads @p component completed a run numbered @p stamp or
    /// later; true when no schedule reads it. Called from a body or between ticks.
    bool (*expired)(ke_scheduler *self, ke_component_id component, uint64_t stamp);
} ke_scheduler;

/// [owner]
typedef struct ke_scheduler_handle {
    ke_scheduler *ref;
    void (*destroy)(ke_scheduler *self);
} ke_scheduler_handle;

/// [value] What a scheduler is created with, each field applied as given.
typedef struct ke_scheduler_config {
    /// The dt of a fixed step, in seconds; greater than zero.
    float fixed_dt;
    /// The most time a tick may accumulate for fixed steps, in seconds; the excess is dropped;
    /// greater than zero.
    float fixed_dt_max_accum;
} ke_scheduler_config;

#ifdef __cplusplus
}
#endif

#endif

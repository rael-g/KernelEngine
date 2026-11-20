#ifndef KERNEL_ENGINE_SCHEDULER_SCHEDULER_H_
#define KERNEL_ENGINE_SCHEDULER_SCHEDULER_H_

#include <kernel_engine/tasks/completion.h>
#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_scheduler ke_scheduler;

/// When an executable runs within the ticks of a scheduler.
typedef enum ke_scheduler_cadence {
    /// Once per tick, with the tick's dt.
    KE_SCHEDULER_CADENCE_EVERY_TICK = 0,
    /// Once per fixed step, as many steps as the tick's time covers, with the fixed dt. Fixed
    /// executables added one after another run together, in order, at each step.
    KE_SCHEDULER_CADENCE_FIXED      = 1,
    /// Once, before every other executable of the first tick, with a dt of zero.
    KE_SCHEDULER_CADENCE_STARTUP    = 2,
    /// Once, when the scheduler shuts down after a tick ran, with a dt of zero.
    KE_SCHEDULER_CADENCE_SHUTDOWN   = 3,
} ke_scheduler_cadence;

/// One run of an executable: a schedule, a render, a script, a test.
/// @param user [context] Forwarded from add.
/// @param out_completion [out] Receives the run's completion, which the scheduler waits on and
///        releases.
/// @return KE_OK, or the code the run could not start with.
typedef ke_result (*ke_scheduler_run_fn)(void *user, float dt, ke_completion **out_completion);

/// [bag] An executable as add takes it: a schedule, the extraction into a render world, a test. A part providing it
/// is bound to one of the scheduler's cadences.
typedef struct ke_scheduler_executable {
    /// Starts one run of the executable.
    ke_scheduler_run_fn run;
    /// [context] Forwarded to @p run, and the name completed_since knows the executable by.
    void *user;
} ke_scheduler_executable;

/// [interface] The frame loop: runs the executables it was given, each when its cadence says, tick
/// by tick, waiting on each run before the next starts. It knows no schedule, render, event or
/// component.
typedef struct ke_scheduler {
    void *handle;

    /// Adds an executable; a tick runs the executables in the order they were added.
    /// @param run [closure:user] Starts one run of the executable.
    /// @param user [context] Forwarded to @p run, and the name completed_since knows the executable
    ///        by.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p run or an unknown cadence;
    ///         KE_RESULT_NOT_SUPPORTED after shutdown; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*add)(ke_scheduler *self, ke_scheduler_run_fn run, void *user, ke_scheduler_cadence cadence);

    /// Drains the job and async systems, then runs the executables: on the first tick the startup
    /// ones first, then each every-tick one, and each block of fixed ones once per fixed step the
    /// accumulated time covers, the accumulation capped at fixed_dt_max_accum.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a negative @p dt; KE_RESULT_NOT_SUPPORTED after
    ///         shutdown; the code a run failed with, no later executable running.
    ke_result (*tick)(ke_scheduler *self, float dt);

    /// Runs the shutdown executables once if a tick ran; a later call does nothing, and a later tick
    /// is refused. Destroying the scheduler calls it for a caller that did not.
    /// @return KE_OK; the code a run failed with.
    ke_result (*shutdown)(ke_scheduler *self);

    /// Records that the program should end; any body or the caller may ask, from any thread.
    void (*request_exit)(ke_scheduler *self);

    /// Whether a request to end the program was recorded.
    bool (*exit_requested)(ke_scheduler *self);

    /// The number of the run started last; every run started takes the next number, and zero means
    /// none started. Readable from any thread; a body stamps what it writes with it.
    uint64_t (*sequence)(ke_scheduler *self);

    /// Whether every executable added with @p user completed a run numbered @p sequence or later;
    /// true when none was added with it. Called from a body or between ticks.
    bool (*completed_since)(ke_scheduler *self, const void *user, uint64_t sequence);

    /// How far the time accumulated toward the next fixed step is, in [0, 1): what the tick's fixed
    /// steps left over divided by fixed_dt. Read between ticks or from a body.
    float (*fixed_alpha)(ke_scheduler *self);
} ke_scheduler;

/// [owner]
typedef struct ke_scheduler_handle {
    ke_scheduler *ref;
    void (*destroy)(ke_scheduler *self);
} ke_scheduler_handle;

/// Setting every scheduler reads, a number: the dt of a fixed step, in seconds; greater than zero.
#define KE_SCHEDULER_SETTING_FIXED_DT "fixed_dt"
/// Setting every scheduler reads, a number: the most time a tick may accumulate for fixed steps, in
/// seconds, the excess dropped; greater than zero.
#define KE_SCHEDULER_SETTING_FIXED_DT_MAX_ACCUM "fixed_dt_max_accum"

#ifdef __cplusplus
}
#endif

#endif

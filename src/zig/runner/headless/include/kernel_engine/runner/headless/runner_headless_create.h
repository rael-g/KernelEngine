#ifndef KERNEL_ENGINE_RUNNER_HEADLESS_RUNNER_HEADLESS_CREATE_H_
#define KERNEL_ENGINE_RUNNER_HEADLESS_RUNNER_HEADLESS_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/input/input.h>
#include <kernel_engine/runner/runner.h>
#include <kernel_engine/scheduler/scheduler.h>
#include <kernel_engine/settings/settings.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_RUNNER_HEADLESS_API
#  ifdef KE_RUNNER_HEADLESS_EXPORT
#    define KE_RUNNER_HEADLESS_API KE_EXPORT
#  else
#    define KE_RUNNER_HEADLESS_API KE_IMPORT
#  endif
#endif

/**
 * Creates a runner with no window: each run ticks @p scheduler a fixed number of frames with a fixed dt, stopping
 * early when the program is asked to end, and before each frame reports to @p input the key transitions a script
 * gives that frame.
 * @param scheduler [borrowed] Ticked by run; must outlive the runner.
 * @param input [borrowed] Receives the script's key transitions; must outlive the runner.
 * @param settings [borrowed] Read once. `frames`, an integer, the frames a run ticks, default 60; `dt`, a number
 *        greater than zero, the seconds each frame ticks, default 1/60; `script`, a string, entries
 *        separated by `;`, each a frame counted from zero, a key named as a project's input maps name it and `down`
 *        or `up`, separated by spaces, as "0 W down; 30 W up", default empty.
 * @param out_runner [out] Receives the runner; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument, or a setting unknown, of another type, out of range
 *         or a script entry that is malformed or names no key; KE_RESULT_OUT_OF_MEMORY.
 */
KE_RUNNER_HEADLESS_API ke_result ke_runner_headless_create(ke_scheduler *scheduler, ke_input *input,
                                                           ke_settings *settings, ke_runner_handle *out_runner);

#ifdef __cplusplus
}
#endif

#endif

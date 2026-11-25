#ifndef KERNEL_ENGINE_RUNNER_WINDOW_RUNNER_WINDOW_CREATE_H_
#define KERNEL_ENGINE_RUNNER_WINDOW_RUNNER_WINDOW_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/scheduling/runner.h>
#include <kernel_engine/scheduling/scheduler.h>
#include <kernel_engine/window/window.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_RUNNER_WINDOW_API
#  ifdef KE_RUNNER_WINDOW_EXPORT
#    define KE_RUNNER_WINDOW_API KE_EXPORT
#  else
#    define KE_RUNNER_WINDOW_API KE_IMPORT
#  endif
#endif

/**
 * Creates a runner over a window: each frame of a run handles @p window's events, then ticks @p scheduler by the
 * seconds measured since the previous frame, the first by none, until the window is closed or the program is
 * asked to end.
 * @param scheduler [borrowed] Ticked by run; must outlive the runner.
 * @param window [borrowed] Whose events run handles; must outlive the runner.
 * @param out_runner [out] Receives the runner; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_OUT_OF_MEMORY.
 */
KE_RUNNER_WINDOW_API ke_result ke_runner_window_create(ke_scheduler *scheduler, ke_window *window,
                                                       ke_runner_handle *out_runner);

#ifdef __cplusplus
}
#endif

#endif

#ifndef KERNEL_ENGINE_COMPLETION_COMPLETION_H_
#define KERNEL_ENGINE_COMPLETION_COMPLETION_H_

#include <kernel_engine/result/result.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_completion ke_completion;

/// [interface] Work that finishes once, with a result: a job, an asynchronous operation, a read, a
/// run, a submission. Whoever received it releases it exactly once; a completion that another call
/// borrowed as a dependency is released only after the work that depends on it completed.
typedef struct ke_completion {
    void *handle;

    /// Whether the work finished; callable from any thread.
    /// @param out_result [out] Receives what the work finished with, when it finished.
    /// @return true once the work finished.
    bool (*poll)(ke_completion *self, ke_result *out_result);

    /// Blocks until the work finishes and returns what it finished with. Callable from the thread
    /// that created the system the completion came from, and from inside a job when the completion
    /// came from that job system.
    /// @return What the work finished with; KE_RESULT_NOT_SUPPORTED, at once, from any other thread,
    ///         where the completion is passed as a dependency instead.
    ke_result (*wait)(ke_completion *self);

    /// Gives the completion back; the pointer is invalid afterwards. The work itself is not stopped.
    void (*release)(ke_completion *self);
} ke_completion;

#ifdef __cplusplus
}
#endif

#endif

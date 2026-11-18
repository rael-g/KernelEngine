#ifndef KERNEL_ENGINE_ASYNC_ASYNC_H_
#define KERNEL_ENGINE_ASYNC_ASYNC_H_

#include <kernel_engine/completion/completion.h>
#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_async ke_async;
typedef struct ke_async_ctx ke_async_ctx;

/// [interface] What an operation sees while it runs.
typedef struct ke_async_ctx {
    void *handle;
    /// [array_of:dep_count] What each dependency finished with, in the order they were given.
    const ke_result *dep_results;
    uint32_t         dep_count;

    /// Whether the operation was cancelled; the body returns early when it sees true.
    bool (*cancelled)(ke_async_ctx *self);
} ke_async_ctx;

/// The body of an operation, run once on a worker that may block in a system call.
/// @param data [context] Forwarded from submit.
/// @param ctx  The dependencies and the cancellation.
/// @return KE_OK, or the code the operation failed with, which its completion carries.
typedef ke_result (*ke_async_fn)(void *data, ke_async_ctx *ctx);

/// [interface] Runs work that tolerates latency and may block, beside the frame.
typedef struct ke_async {
    void *handle;

    /// Runs @p fn once every dependency finished. Callable from any thread.
    /// @param label [utf8,nullable] Names the operation in profiles and logs; copied.
    /// @param fn [closure:data] The body.
    /// @param data [borrowed] Forwarded to @p fn unchanged.
    /// @param deps [borrowed,array_of:dep_count] Completions of any origin.
    /// @param out_completion [out] Receives the operation's completion, which the caller releases.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p fn, @p out_completion, or a null
    ///         dependency; KE_RESULT_OUT_OF_MEMORY, also when the queue for other threads is full.
    ke_result (*submit)(ke_async *self, const char *label, ke_async_fn fn, void *data,
                        ke_completion *const *deps, uint32_t dep_count,
                        ke_completion **out_completion);

    /// Asks the operation behind @p completion to stop: one not started finishes with
    /// KE_RESULT_CANCELLED without running, one running sees cancelled. Callable from any thread.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a completion this system did not give.
    ke_result (*cancel)(ke_async *self, ke_completion *completion);

    /// Advances the work submitted from other threads and the work that waits on completions of
    /// another origin; called by the thread that created the system, which does nothing from any
    /// other. Doing nothing is a valid answer.
    void (*drain)(ke_async *self);
} ke_async;

/// [owner]
typedef struct ke_async_handle {
    ke_async *ref;
    void (*destroy)(ke_async *self);
} ke_async_handle;

/// Setting every async system reads, an integer: the worker threads besides the creating thread; 0
/// runs every operation on the creating thread when it drains.
#define KE_ASYNC_SETTING_WORKER_COUNT "worker_count"

#ifdef __cplusplus
}
#endif

#endif

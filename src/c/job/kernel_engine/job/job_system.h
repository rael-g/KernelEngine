#ifndef KERNEL_ENGINE_JOB_JOB_SYSTEM_H_
#define KERNEL_ENGINE_JOB_JOB_SYSTEM_H_

#include <kernel_engine/completion/completion.h>
#include <kernel_engine/result/result.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_job_system ke_job_system;

/// [value] What a job sees of its dependencies when it starts.
typedef struct ke_job_ctx {
    /// [array_of:dep_count] What each dependency finished with, in the order they were given.
    const ke_result *dep_results;
    uint32_t         dep_count;
} ke_job_ctx;

/// The body of a job, run once on a worker after every dependency finished, whatever each
/// finished with.
/// @param data [context] Forwarded from dispatch.
/// @param ctx  The results of the dependencies.
/// @return KE_OK, or the code the job failed with, which its completion carries.
typedef ke_result (*ke_job_fn)(void *data, const ke_job_ctx *ctx);

/// One range of a parallel_for, run on a worker; ranges cover [0, item_count) without overlap.
/// @param data         [context] Forwarded from parallel_for.
/// @param worker_index Unique among the threads running at once, in [0, worker_slots).
/// @return KE_OK, or the code the range failed with; the first failure is what the completion
///         carries.
typedef ke_result (*ke_job_range_fn)(void *data, uint32_t start, uint32_t end, uint32_t worker_index);

/// [interface] Runs the work of a frame on workers, each piece after the completions it depends on.
/// Work that does not fit in a frame belongs to the async system. Jobs are never cancelled.
typedef struct ke_job_system {
    void *handle;

    /// Runs @p fn once every dependency finished. Callable from the thread that created the system
    /// and from inside a job.
    /// @param label [utf8,nullable] Names the job in profiles and logs; copied.
    /// @param fn [closure:data] The body.
    /// @param data [borrowed] Forwarded to @p fn unchanged.
    /// @param deps [borrowed,array_of:dep_count] Completions of any origin.
    /// @param out_completion [out] Receives the job's completion, which the caller releases.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p fn, @p out_completion, or a null
    ///         dependency; KE_RESULT_NOT_SUPPORTED from any other thread; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*dispatch)(ke_job_system *self, const char *label, ke_job_fn fn, void *data,
                          ke_completion *const *deps, uint32_t dep_count,
                          ke_completion **out_completion);

    /// Runs @p fn over [0, @p item_count) in ranges, once every dependency finished. Callable from
    /// the thread that created the system and from inside a job.
    /// @param label [utf8,nullable] Names the work in profiles and logs; copied.
    /// @param fn [closure:data] The body of each range.
    /// @param data [borrowed] Forwarded to @p fn unchanged.
    /// @param min_range The fewest items a range should hold; a hint the system may ignore.
    /// @param deps [borrowed,array_of:dep_count] Completions of any origin.
    /// @param out_completion [out] Receives the completion of every range, which the caller releases.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p fn, @p out_completion, or a null
    ///         dependency; KE_RESULT_NOT_SUPPORTED from any other thread; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*parallel_for)(ke_job_system *self, const char *label, ke_job_range_fn fn, void *data,
                              uint32_t item_count, uint32_t min_range,
                              ke_completion *const *deps, uint32_t dep_count,
                              ke_completion **out_completion);

    /// The number of distinct worker indices a range may see.
    uint32_t (*worker_slots)(ke_job_system *self);

    /// Advances the work that waits on completions of another origin; called by the thread that
    /// created the system, which does nothing from any other. Doing nothing is a valid answer.
    void (*drain)(ke_job_system *self);
} ke_job_system;

/// [owner]
typedef struct ke_job_system_handle {
    ke_job_system *ref;
    void (*destroy)(ke_job_system *self);
} ke_job_system_handle;

/// Setting every job system reads, an integer: the worker threads besides the creating thread; 0 runs
/// every job on the creating thread.
#define KE_JOB_SYSTEM_SETTING_WORKER_COUNT "worker_count"

#ifdef __cplusplus
}
#endif

#endif

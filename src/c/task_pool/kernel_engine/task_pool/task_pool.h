#ifndef KERNEL_ENGINE_TASK_POOL_TASK_POOL_H_
#define KERNEL_ENGINE_TASK_POOL_TASK_POOL_H_

#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_task_pool ke_task_pool;
    typedef struct ke_task ke_task;

    /**
     * Body of a scheduled task, run on a worker thread.
     * @param data [context] [borrowed] Opaque context handed to the dispatch call.
     * @return KE_OK, or the code the body failed with, which wait() returns.
     */
    typedef ke_result (*ke_task_func)(void *data);

    /**
     * Run once the task body has returned, on the same worker thread.
     * @param task      The task that finished.
     * @param user_data [context] Opaque context handed to the dispatch call.
     * @param result What the body returned.
     */
    typedef void (*ke_task_on_complete_func)(ke_task *task, void *user_data, ke_result result);

    /** [interface] Dispatches work to a native thread pool. */
    typedef struct ke_task_pool
    {
        void *handle;

        /**
         * Schedules a task, which the caller releases by waiting on it.
         * @param func [raw_callback] [closure:data] Entry point invoked on a worker thread.
         * @param data [borrowed] Opaque context passed to func unchanged.
         * @param out_task [out] Receives the task; null on failure.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p func or @p out_task,
         *         KE_RESULT_OUT_OF_MEMORY, or KE_RESULT_NOT_SUPPORTED when the pool does
         *         not accept the calling thread.
         */
        ke_result (*dispatch)(struct ke_task_pool *self, ke_task_func func, void *data,
                              ke_task **out_task);

        /**
         * Schedules a task and a completion callback run once it finishes.
         * @param func [raw_callback] [closure:data] Entry point invoked on a worker thread.
         * @param data [borrowed] Opaque context passed to func unchanged.
         * @param on_complete [raw_callback] [closure:user_data] Invoked after func returns.
         * @param user_data [borrowed] Opaque context passed to on_complete unchanged.
         * @param out_task [out] Receives the task; null on failure.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p func or @p out_task,
         *         KE_RESULT_OUT_OF_MEMORY, or KE_RESULT_NOT_SUPPORTED when the pool does
         *         not accept the calling thread.
         */
        ke_result (*dispatch_on_complete)(struct ke_task_pool *self,
                                          ke_task_func func, void *data,
                                          ke_task_on_complete_func on_complete,
                                          void *user_data, ke_task **out_task);

        /**
         * Blocks the calling thread until the task completes, releases the task, and returns
         * what its body returned. Every task a dispatch slot returns is waited on exactly once:
         * afterwards the pointer is invalid for wait and is_completed alike, and a task never
         * waited on is never released and reports its failure nowhere.
         * @return What the task body returned, or KE_RESULT_INVALID_ARGUMENT for a null task.
         */
        ke_result (*wait)(struct ke_task_pool *self, ke_task *task);

        /** Returns true if the task has finished. Valid only before the task is waited on. */
        bool (*is_completed)(struct ke_task_pool *self, ke_task *task);

        /** Returns the number of worker threads in the pool. */
        uint32_t (*get_num_workers)(struct ke_task_pool *self);

    } ke_task_pool;

    /// [owner]
    typedef struct ke_task_pool_handle
    {
        ke_task_pool *ref;
        void (*destroy)(ke_task_pool *self);
    } ke_task_pool_handle;

#ifdef __cplusplus
}
#endif

#endif

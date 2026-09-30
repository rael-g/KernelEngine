#ifndef KERNEL_ENGINE_SCHEDULER_SCHEDULER_H_
#define KERNEL_ENGINE_SCHEDULER_SCHEDULER_H_

#include <kernel_engine/common/error.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_scheduler ke_scheduler;
    typedef struct ke_task ke_task;

    /**
     * Body of a scheduled task, run on a worker thread.
     *
     * The failure is reported as a type rather than a ke_error because the two travel
     * differently: a ke_error_type is an immortal singleton, while a ke_error points into
     * the failing thread's own storage and is recycled by the failures after it. The task
     * outlives the thread that ran it, so only the type can make the trip. The caller of
     * wait() mints a ke_error from it on its own thread.
     *
     * @param data        [context] [borrowed] Opaque context handed to the dispatch call.
     * @param out_failure Receives the type the body failed with. Left untouched on success.
     */
    typedef void (*ke_task_func)(void *data, const ke_error_type **out_failure);

    /**
     * Run once the task body has returned, on the same worker thread.
     * @param task      The task that finished.
     * @param user_data [context] Opaque context handed to the dispatch call.
     * @param failure The type the body failed with, or NULL when it succeeded.
     */
    typedef void (*ke_task_on_complete_func)(ke_task *task, void *user_data, const ke_error_type *failure);

    /** Dispatches work to a native thread pool. */
    typedef struct ke_scheduler
    {
        void *handle;

        /**
         * Schedules a fire-and-forget task.
         * @param func [raw_callback] [closure:data] Entry point invoked on a worker thread.
         * @param data [borrowed] Opaque context passed to func unchanged.
         */
        ke_task *(*dispatch)(struct ke_scheduler *self, ke_task_func func, void *data);

        /**
         * Schedules a task and a completion callback run once it finishes.
         * @param func [raw_callback] [closure:data] Entry point invoked on a worker thread.
         * @param data [borrowed] Opaque context passed to func unchanged.
         * @param on_complete [raw_callback] [closure:user_data] Invoked after func returns.
         * @param user_data [borrowed] Opaque context passed to on_complete unchanged.
         */
        ke_task *(*dispatch_on_complete)(struct ke_scheduler *self,
                                          ke_task_func func, void *data,
                                          ke_task_on_complete_func on_complete,
                                          void *user_data);

        /**
         * Blocks the calling thread until the task completes, then reports whatever the
         * task body failed with. A task nobody waits on carries its failure to its grave,
         * which is why a dispatch with no completion channel cannot be projected.
         *
         * The error is raised here, on the waiting thread, from the type the body named.
         * What the body meant by it does not survive the crossing: the message names the
         * slot rather than the failure.
         */
        bool (*wait)(struct ke_scheduler *self, ke_task *task, ke_error **out_error);

        /** Returns true if the task has finished. */
        bool (*is_completed)(struct ke_scheduler *self, ke_task *task);

        /**
         * Schedules a fire-and-forget task on one specific worker thread.
         * @param thread_num Index of the worker to run on.
         * @param func [raw_callback] [closure:data] Entry point invoked on that worker thread.
         * @param data [borrowed] Opaque context passed to func unchanged.
         */
        ke_task *(*dispatch_pinned)(struct ke_scheduler *self,
                                     uint32_t             thread_num,
                                     ke_task_func         func,
                                     void                *data);

        /** Returns the number of worker threads in the pool. */
        uint32_t (*get_num_workers)(struct ke_scheduler *self);

    } ke_scheduler;

    typedef struct ke_scheduler_handle
    {
        ke_scheduler *ref;
        void (*destroy)(ke_scheduler *self);
    } ke_scheduler_handle;

#ifdef __cplusplus
}
#endif

#endif

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

    typedef void (*ke_task_func)(void *data);
    typedef void (*ke_task_on_complete_func)(ke_task *task, void *user_data);

    /** Dispatches work to a native thread pool. */
    typedef struct ke_scheduler
    {
        void *handle;

        /**
         * Schedules a fire-and-forget task.
         * @param func [raw_callback] Entry point invoked on a worker thread.
         * @param data [borrowed] Opaque context passed to func unchanged.
         */
        ke_task *(*dispatch)(struct ke_scheduler *self, ke_task_func func, void *data);

        /**
         * Schedules a task and a completion callback run once it finishes.
         * @param func [raw_callback] Entry point invoked on a worker thread.
         * @param data [borrowed] Opaque context passed to func unchanged.
         * @param on_complete [raw_callback] Invoked after func returns.
         * @param user_data [borrowed] Opaque context passed to on_complete unchanged.
         */
        ke_task *(*dispatch_on_complete)(struct ke_scheduler *self,
                                          ke_task_func func, void *data,
                                          ke_task_on_complete_func on_complete,
                                          void *user_data);

        /** Blocks the calling thread until the task completes. */
        void (*wait)(struct ke_scheduler *self, ke_task *task);

        /** Returns true if the task has finished. */
        bool (*is_completed)(struct ke_scheduler *self, ke_task *task);

        /**
         * Schedules a fire-and-forget task on one specific worker thread.
         * @param thread_num Index of the worker to run on.
         * @param func [raw_callback] Entry point invoked on that worker thread.
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

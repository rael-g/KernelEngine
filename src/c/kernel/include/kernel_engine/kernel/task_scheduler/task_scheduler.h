#ifndef KERNEL_ENGINE_KERNEL_TASK_SCHEDULER_TASK_SCHEDULER_H_
#define KERNEL_ENGINE_KERNEL_TASK_SCHEDULER_TASK_SCHEDULER_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_task_scheduler ke_task_scheduler;
    typedef struct ke_task ke_task;

    /**
     * @brief Function signature for a task to be executed.
     */
    typedef void (*ke_task_func)(void *data);

    /**
     * @brief Callback function when a task finishes.
     */
    typedef void (*ke_task_on_complete_func)(ke_task *task, void *user_data);

    /**
     * @brief Interface for a multi-threaded task scheduler.
     */
    typedef struct ke_task_scheduler
    {
        void *handle;

        /**
         * @brief Destroys the task scheduler and its thread pool.
         */
        void (*destroy)(struct ke_task_scheduler *self);

        /**
         * @brief Schedules a function to run on the task pool.
         * @param func The function to execute.
         * @param data User data passed to the function.
         * @return A handle to the created task. Memory is managed by the scheduler.
         */
        ke_task *(*dispatch)(struct ke_task_scheduler *self, ke_task_func func, void *data);

        /**
         * @brief Schedules a task and registers a callback to be invoked on completion.
         * Useful for bridging to async/await or message pipes.
         */
        ke_task *(*dispatch_on_complete)(struct ke_task_scheduler *self, ke_task_func func, void *data, ke_task_on_complete_func on_complete, void *user_data);

        /**
         * @brief Blocks the current thread until the task is finished.
         */
        void (*wait)(struct ke_task_scheduler *self, ke_task *task);

        /**
         * @brief Checks if a task is completed without blocking.
         */
        bool (*is_completed)(struct ke_task_scheduler *self, ke_task *task);

    } ke_task_scheduler;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_TASK_SCHEDULER_TASK_SCHEDULER_H_

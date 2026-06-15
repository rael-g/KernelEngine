#ifndef KERNEL_ENGINE_TASK_SCHEDULER_TASK_SCHEDULER_H_
#define KERNEL_ENGINE_TASK_SCHEDULER_TASK_SCHEDULER_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_task_scheduler ke_task_scheduler;
    typedef struct ke_task ke_task;

    typedef void (*ke_task_func)(void *data);
    typedef void (*ke_task_on_complete_func)(ke_task *task, void *user_data);

    typedef struct ke_task_scheduler
    {
        void *handle;

        void (*destroy)(struct ke_task_scheduler *self);

        ke_task *(*dispatch)(struct ke_task_scheduler *self, ke_task_func func, void *data);

        ke_task *(*dispatch_on_complete)(struct ke_task_scheduler *self,
                                          ke_task_func func, void *data,
                                          ke_task_on_complete_func on_complete,
                                          void *user_data);

        void (*wait)(struct ke_task_scheduler *self, ke_task *task);

        bool (*is_completed)(struct ke_task_scheduler *self, ke_task *task);

        ke_task *(*dispatch_pinned)(struct ke_task_scheduler *self,
                                     uint32_t                  thread_num,
                                     ke_task_func              func,
                                     void                     *data);

        uint32_t (*get_num_workers)(struct ke_task_scheduler *self);

    } ke_task_scheduler;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_TASK_SCHEDULER_TASK_SCHEDULER_H_

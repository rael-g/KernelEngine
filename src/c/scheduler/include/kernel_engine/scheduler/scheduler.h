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

    // TODO: a task carries no built-in result/error today — async operations
    // write outcomes into their own `data` ctx, read after wait(). A typed
    // result/error slot on ke_task would let cross-thread async failures
    // propagate through the scheduler without each caller reinventing that
    // convention. Until then: the thread-local slot behind ke_error cannot be
    // read from another thread, so a failure that has to cross one travels as a
    // program-lifetime error constant the task hands to its completion callback.
    typedef void (*ke_task_func)(void *data);
    typedef void (*ke_task_on_complete_func)(ke_task *task, void *user_data);

    typedef struct ke_scheduler
    {
        void *handle;

        ke_task *(*dispatch)(struct ke_scheduler *self, ke_task_func func, void *data);

        ke_task *(*dispatch_on_complete)(struct ke_scheduler *self,
                                          ke_task_func func, void *data,
                                          ke_task_on_complete_func on_complete,
                                          void *user_data);

        void (*wait)(struct ke_scheduler *self, ke_task *task);

        bool (*is_completed)(struct ke_scheduler *self, ke_task *task);

        ke_task *(*dispatch_pinned)(struct ke_scheduler *self,
                                     uint32_t             thread_num,
                                     ke_task_func         func,
                                     void                *data);

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

#endif // KERNEL_ENGINE_SCHEDULER_SCHEDULER_H_

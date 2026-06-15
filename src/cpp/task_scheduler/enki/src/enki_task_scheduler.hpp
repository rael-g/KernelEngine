#pragma once

#include <kernel_engine/task_scheduler/task_scheduler.h>
#include <kernel_engine/task_scheduler/enki/enki_task_scheduler.h>
#include <atomic>

namespace enki { class TaskScheduler; class ITaskSet; }

namespace kernel_engine::task_scheduler::enki {

class EnkiTaskScheduler {
public:
    EnkiTaskScheduler(struct ke_allocator* alloc);
    ~EnkiTaskScheduler();

    struct ke_task_scheduler* ToApi();

private:
    void* scheduler_ptr_; 
    struct ke_allocator* allocator_;
    struct ke_task_scheduler api_{};
};

} // namespace kernel_engine::task_scheduler::enki

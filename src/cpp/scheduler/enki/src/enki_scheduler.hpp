#pragma once

#include <kernel_engine/scheduler/scheduler.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>
#include <atomic>

namespace enki { class TaskScheduler; class ITaskSet; }

namespace kernel_engine::scheduler::enki {

class EnkiScheduler {
public:
    EnkiScheduler();
    ~EnkiScheduler();

    struct ke_scheduler* ToApi();

    /// Owner-handle destroy: tears down the scheduler and frees its allocation.
    static void DestroyApi(struct ke_scheduler* self);

private:
    void* scheduler_ptr_;
    struct ke_scheduler api_{};
};

} // namespace kernel_engine::scheduler::enki

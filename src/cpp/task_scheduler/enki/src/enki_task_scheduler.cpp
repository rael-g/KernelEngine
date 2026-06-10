#include "enki_task_scheduler.hpp"
#include <TaskScheduler.h>
#include <atomic>
#include <new>

namespace kernel_engine::task_scheduler::enki {

class EnkiTask : public ::enki::ITaskSet {
public:
    ke_task_func func = nullptr;
    void* data = nullptr;
    ke_task_on_complete_func on_complete = nullptr;
    void* on_complete_user_data = nullptr;
    std::atomic<bool> completed{false};

    void ExecuteRange(::enki::TaskSetPartition range, uint32_t threadnum) override {
        (void)range;
        (void)threadnum;
        if (func) func(data);
        completed.store(true, std::memory_order_release);
        
        if (on_complete) {
            on_complete(reinterpret_cast<ke_task*>(this), on_complete_user_data);
        }
    }
};

EnkiTaskScheduler::EnkiTaskScheduler(ke_allocator* alloc) : allocator_(alloc) {
    auto* scheduler = new ::enki::TaskScheduler();
    scheduler->Initialize();
    scheduler_ptr_ = scheduler;
    
    api_.handle = this;
    api_.destroy = [](ke_task_scheduler* self) {
        if (!self) return;
        auto* internal = static_cast<EnkiTaskScheduler*>(self->handle);
        auto* alloc = internal->allocator_;
        internal->~EnkiTaskScheduler();
        alloc->free(alloc, internal);
    };

    api_.dispatch = [](ke_task_scheduler* self, ke_task_func func, void* data) -> ke_task* {
        if (!self || !self->handle || !func) return nullptr;
        return self->dispatch_on_complete(self, func, data, nullptr, nullptr);
    };

    api_.dispatch_on_complete = [](ke_task_scheduler* self, ke_task_func func, void* data, ke_task_on_complete_func on_complete, void* user_data) -> ke_task* {
        if (!self || !self->handle || !func) return nullptr;
        auto* internal = static_cast<EnkiTaskScheduler*>(self->handle);
        auto* scheduler = static_cast<::enki::TaskScheduler*>(internal->scheduler_ptr_);
        
        void* task_mem = internal->allocator_->alloc(internal->allocator_, sizeof(EnkiTask), alignof(EnkiTask));
        if (!task_mem) return nullptr;

        EnkiTask* task = new (task_mem) EnkiTask();
        task->func = func;
        task->data = data;
        task->on_complete = on_complete;
        task->on_complete_user_data = user_data;
        
        scheduler->AddTaskSetToPipe(task);
        return reinterpret_cast<ke_task*>(task);
    };

    api_.wait = [](ke_task_scheduler* self, ke_task* task) {
        if (!self || !task) return;
        auto* internal = static_cast<EnkiTaskScheduler*>(self->handle);
        auto* scheduler = static_cast<::enki::TaskScheduler*>(internal->scheduler_ptr_);
        auto* enki_task = reinterpret_cast<EnkiTask*>(task);
        
        scheduler->WaitforTask(enki_task);
        
        enki_task->~EnkiTask();
        internal->allocator_->free(internal->allocator_, enki_task);
    };

    api_.is_completed = [](ke_task_scheduler* self, ke_task* task) -> bool {
        if (!task) return true;
        auto* enki_task = reinterpret_cast<EnkiTask*>(task);
        return enki_task->completed.load(std::memory_order_acquire);
    };
}

EnkiTaskScheduler::~EnkiTaskScheduler() {
    auto* scheduler = static_cast<::enki::TaskScheduler*>(scheduler_ptr_);
    scheduler->WaitforAll();
    delete scheduler;
}

ke_task_scheduler* EnkiTaskScheduler::ToApi() {
    return &api_;
}

} // namespace kernel_engine::task_scheduler::enki

extern "C" {
    ke_result ke_task_scheduler_enki_create(ke_allocator *allocator, ke_task_scheduler **out_scheduler) {
        if (!allocator || !out_scheduler) return KE_ERROR_INVALID_ARGUMENT;

        void* mem = allocator->alloc(allocator, sizeof(kernel_engine::task_scheduler::enki::EnkiTaskScheduler), alignof(kernel_engine::task_scheduler::enki::EnkiTaskScheduler));
        if (!mem) return KE_ERROR_OUT_OF_MEMORY;

        auto* internal = new (mem) kernel_engine::task_scheduler::enki::EnkiTaskScheduler(allocator);
        *out_scheduler = internal->ToApi();
        
        return KE_OK;
    }
}

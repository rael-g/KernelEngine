#include "enki_task_scheduler.hpp"
#include <kernel_engine/common/error.h>
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

// Pinned variant — same shape, different enki base class. enki dispatches it
// only on the worker thread whose id matches `threadNum` (set via IPinnedTask
// ctor). Used by render-thread-affine systems.
class EnkiPinnedTask : public ::enki::IPinnedTask {
public:
    ke_task_func func = nullptr;
    void* data = nullptr;
    std::atomic<bool> completed{false};

    EnkiPinnedTask() = default;
    EnkiPinnedTask(uint32_t threadNum) : ::enki::IPinnedTask(threadNum) {}

    void Execute() override {
        if (func) func(data);
        completed.store(true, std::memory_order_release);
    }
};

EnkiTaskScheduler::EnkiTaskScheduler(ke_allocator* alloc) : allocator_(alloc) {
    auto* scheduler = new ::enki::TaskScheduler();
    scheduler->Initialize();
    scheduler_ptr_ = scheduler;
    
    api_.handle = this;
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

    // ke_task* uses low-bit tagging: bit 0 set = EnkiPinnedTask, clear = EnkiTask.
    // Lets wait/is_completed dispatch to the right type without an extra header.
    // Both EnkiTask and EnkiPinnedTask are 8-byte aligned, so bit 0 is always
    // free for the tag.

    api_.wait = [](ke_task_scheduler* self, ke_task* task) {
        if (!self || !task) return;
        auto* internal = static_cast<EnkiTaskScheduler*>(self->handle);
        auto* scheduler = static_cast<::enki::TaskScheduler*>(internal->scheduler_ptr_);

        uintptr_t raw = reinterpret_cast<uintptr_t>(task);
        bool pinned = (raw & 1u) != 0;
        void* ptr = reinterpret_cast<void*>(raw & ~uintptr_t(1));

        if (pinned) {
            auto* pt = static_cast<EnkiPinnedTask*>(ptr);
            scheduler->WaitforTask(pt);
            pt->~EnkiPinnedTask();
            internal->allocator_->free(internal->allocator_, pt);
        } else {
            auto* nt = static_cast<EnkiTask*>(ptr);
            scheduler->WaitforTask(nt);
            nt->~EnkiTask();
            internal->allocator_->free(internal->allocator_, nt);
        }
    };

    api_.is_completed = [](ke_task_scheduler* self, ke_task* task) -> bool {
        (void)self;
        if (!task) return true;
        uintptr_t raw = reinterpret_cast<uintptr_t>(task);
        bool pinned = (raw & 1u) != 0;
        void* ptr = reinterpret_cast<void*>(raw & ~uintptr_t(1));
        if (pinned) {
            return static_cast<EnkiPinnedTask*>(ptr)->completed.load(std::memory_order_acquire);
        }
        return static_cast<EnkiTask*>(ptr)->completed.load(std::memory_order_acquire);
    };

    api_.dispatch_pinned = [](ke_task_scheduler* self, uint32_t thread_num,
                               ke_task_func func, void* data) -> ke_task* {
        if (!self || !self->handle || !func) return nullptr;
        auto* internal = static_cast<EnkiTaskScheduler*>(self->handle);
        auto* scheduler = static_cast<::enki::TaskScheduler*>(internal->scheduler_ptr_);

        void* task_mem = internal->allocator_->alloc(internal->allocator_,
            sizeof(EnkiPinnedTask), alignof(EnkiPinnedTask));
        if (!task_mem) return nullptr;

        EnkiPinnedTask* task = new (task_mem) EnkiPinnedTask(thread_num);
        task->func = func;
        task->data = data;

        scheduler->AddPinnedTask(task);
        // Tag the low bit so wait()/is_completed() route to the pinned-task path.
        return reinterpret_cast<ke_task*>(reinterpret_cast<uintptr_t>(task) | uintptr_t(1));
    };

    api_.get_num_workers = [](ke_task_scheduler* self) -> uint32_t {
        if (!self || !self->handle) return 0;
        auto* internal = static_cast<EnkiTaskScheduler*>(self->handle);
        auto* scheduler = static_cast<::enki::TaskScheduler*>(internal->scheduler_ptr_);
        // GetNumTaskThreads returns total threads including the main thread (id 0).
        // Workers are 1..N-1, so we report (total - 1).
        uint32_t total = scheduler->GetNumTaskThreads();
        return total > 0 ? total - 1 : 0;
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

void EnkiTaskScheduler::DestroyApi(ke_task_scheduler* self) {
    if (!self) return;
    auto* internal = static_cast<EnkiTaskScheduler*>(self->handle);
    auto* alloc = internal->allocator_;
    internal->~EnkiTaskScheduler();
    alloc->free(alloc, internal);
}

} // namespace kernel_engine::task_scheduler::enki

extern "C" {
    ke_result ke_task_scheduler_enki_create(ke_allocator *allocator, ke_task_scheduler_handle *out_scheduler, ke_error **out_error) {
        if (!allocator || !out_scheduler) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");

        void* mem = allocator->alloc(allocator, sizeof(kernel_engine::task_scheduler::enki::EnkiTaskScheduler), alignof(kernel_engine::task_scheduler::enki::EnkiTaskScheduler));
        if (!mem) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "allocation failed");

        auto* internal = new (mem) kernel_engine::task_scheduler::enki::EnkiTaskScheduler(allocator);
        out_scheduler->ref     = internal->ToApi();
        out_scheduler->destroy = &kernel_engine::task_scheduler::enki::EnkiTaskScheduler::DestroyApi;

        return KE_OK;
    }
}

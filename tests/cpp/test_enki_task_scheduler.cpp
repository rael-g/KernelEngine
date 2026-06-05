#include <gtest/gtest.h>
#include <kernel_engine/task_scheduler/enki/enki_task_scheduler.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <atomic>
#include <chrono>
#include <thread>

class EnkiTaskSchedulerTest : public ::testing::Test {
protected:
    ke_allocator* allocator = nullptr;
    ke_task_scheduler* scheduler = nullptr;

    void SetUp() override {
        allocator = ke_allocator_malloc_create();
        ke_result res = ke_task_scheduler_enki_create(allocator, &scheduler);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (scheduler) {
            scheduler->destroy(scheduler);
        }
        if (allocator) {
            allocator->destroy(allocator);
        }
    }
};

TEST_F(EnkiTaskSchedulerTest, Dispatch_ExecutesTask) {
    std::atomic<bool> ran{false};
    ke_task* task = scheduler->dispatch(scheduler, [](void* d) {
        *static_cast<std::atomic<bool>*>(d) = true;
    }, &ran);

    ASSERT_NE(task, nullptr);
    scheduler->wait(scheduler, task);
    ASSERT_TRUE(ran.load());
}

TEST_F(EnkiTaskSchedulerTest, DispatchOnComplete_CallsCallback) {
    std::atomic<bool> ran{false};
    std::atomic<bool> completed{false};
    
    ke_task* task = scheduler->dispatch_on_complete(
        scheduler,
        [](void* d) { *static_cast<std::atomic<bool>*>(d) = true; },
        &ran,
        [](ke_task*, void* d) { *static_cast<std::atomic<bool>*>(d) = true; },
        &completed
    );

    ASSERT_NE(task, nullptr);
    scheduler->wait(scheduler, task);
    ASSERT_TRUE(ran.load());
    ASSERT_TRUE(completed.load());
}

TEST_F(EnkiTaskSchedulerTest, IsCompleted_Works) {
    std::atomic<bool> can_finish{false};
    ke_task* task = scheduler->dispatch(scheduler, [](void* d) {
        while (!static_cast<std::atomic<bool>*>(d)->load()) {
            std::this_thread::yield();
        }
    }, &can_finish);

    // It might still be false or true depending on timing, but after wait it MUST be true.
    can_finish.store(true);
    scheduler->wait(scheduler, task);
    ASSERT_TRUE(scheduler->is_completed(scheduler, task));
}

TEST_F(EnkiTaskSchedulerTest, MultipleTasks_ParallelExecution) {
    std::atomic<int> counter{0};
    const int num_tasks = 20;
    ke_task* tasks[num_tasks];

    for (int i = 0; i < num_tasks; ++i) {
        tasks[i] = scheduler->dispatch(scheduler, [](void* d) {
            static_cast<std::atomic<int>*>(d)->fetch_add(1);
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }, &counter);
    }

    for (int i = 0; i < num_tasks; ++i) {
        scheduler->wait(scheduler, tasks[i]);
    }

    ASSERT_EQ(counter.load(), num_tasks);
}

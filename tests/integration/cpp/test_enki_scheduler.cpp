#include <gtest/gtest.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>
#include <atomic>
#include <chrono>
#include <thread>

class EnkiSchedulerTest : public ::testing::Test {
protected:
    ke_scheduler_handle scheduler_h{};
    ke_scheduler* scheduler = nullptr;

    void SetUp() override {
        ke_result res = ke_scheduler_enki_create(&scheduler_h, NULL);
        ASSERT_EQ(res, KE_OK);
        scheduler = scheduler_h.ref;
    }

    void TearDown() override {
        if (scheduler_h.ref) {
            scheduler_h.destroy(scheduler_h.ref);
        }
    }
};

TEST_F(EnkiSchedulerTest, Dispatch_ExecutesTask) {
    std::atomic<bool> ran{false};
    ke_task* task = scheduler->dispatch(scheduler, [](void* d) {
        *static_cast<std::atomic<bool>*>(d) = true;
    }, &ran);

    ASSERT_NE(task, nullptr);
    scheduler->wait(scheduler, task);
    ASSERT_TRUE(ran.load());
}

TEST_F(EnkiSchedulerTest, DispatchOnComplete_CallsCallback) {
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

TEST_F(EnkiSchedulerTest, IsCompleted_Works) {
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

TEST_F(EnkiSchedulerTest, API_NullChecks) {
    ASSERT_EQ(scheduler->dispatch(nullptr, nullptr, nullptr), nullptr);
    ASSERT_EQ(scheduler->dispatch(scheduler, nullptr, nullptr), nullptr);
    
    ASSERT_EQ(scheduler->dispatch_on_complete(nullptr, nullptr, nullptr, nullptr, nullptr), nullptr);
    ASSERT_EQ(scheduler->dispatch_on_complete(scheduler, nullptr, nullptr, nullptr, nullptr), nullptr);
    
    scheduler->wait(nullptr, nullptr);
    scheduler->wait(scheduler, nullptr);

    // Documented semantic: a null task is treated as "no task to wait on, therefore
    // complete" so polling loops on stale handles exit cleanly. Defensive callers
    // should still pass valid task pointers; null is a safety net, not a contract.
    ASSERT_TRUE(scheduler->is_completed(scheduler, nullptr));
}

TEST_F(EnkiSchedulerTest, Destroy_NullSelf_IsSafe) {
    auto d = scheduler_h.destroy;
    scheduler_h.destroy(scheduler_h.ref);
    scheduler = nullptr;
    scheduler_h = {};
    d(nullptr);
}

#include <gtest/gtest.h>
#include <kernel_engine/scheduler/scheduler.h>
#include <atomic>
#include <cstdlib>

// ── Synchronous mock scheduler (no OS threads) ────────────────────────────────
//
// Executes tasks immediately on the calling thread so tests are deterministic.

namespace {

struct MockTask {
    ke_task_func             func;
    void*                    data;
    ke_task_on_complete_func on_complete;
    void*                    on_complete_user_data;
    bool                     completed;
};

ke_scheduler make_sync_scheduler() {
    ke_scheduler s{};
    s.handle = nullptr;

    s.destroy = [](ke_scheduler*) {};

    s.dispatch_on_complete = [](ke_scheduler* self,
                                ke_task_func func, void* data,
                                ke_task_on_complete_func on_complete,
                                void* user_data) -> ke_task* {
        auto* task = new MockTask{ func, data, on_complete, user_data, false };
        if (func) func(data);
        task->completed = true;
        if (on_complete) on_complete(reinterpret_cast<ke_task*>(task), user_data);
        return reinterpret_cast<ke_task*>(task);
    };

    s.dispatch = [](ke_scheduler* self, ke_task_func func, void* data) -> ke_task* {
        return self->dispatch_on_complete(self, func, data, nullptr, nullptr);
    };

    s.wait = [](ke_scheduler*, ke_task* task) {
        delete reinterpret_cast<MockTask*>(task);
    };

    s.is_completed = [](ke_scheduler*, ke_task* task) -> bool {
        if (!task) return true;
        return reinterpret_cast<MockTask*>(task)->completed;
    };

    return s;
}

} // namespace

// ── Tests ─────────────────────────────────────────────────────────────────────

class TaskSchedulerTest : public ::testing::Test {
protected:
    ke_scheduler scheduler{};

    void SetUp() override { scheduler = make_sync_scheduler(); }
    void TearDown() override { scheduler.destroy(&scheduler); }
};

TEST_F(TaskSchedulerTest, Dispatch_ExecutesTask) {
    bool ran = false;
    ke_task* task = scheduler.dispatch(&scheduler, [](void* d) {
        *static_cast<bool*>(d) = true;
    }, &ran);

    ASSERT_TRUE(ran);
    scheduler.wait(&scheduler, task);
}

TEST_F(TaskSchedulerTest, Dispatch_IsCompleted_ReturnsTrueAfterRun) {
    ke_task* task = scheduler.dispatch(&scheduler, [](void*) {}, nullptr);
    ASSERT_TRUE(scheduler.is_completed(&scheduler, task));
    scheduler.wait(&scheduler, task);
}

TEST_F(TaskSchedulerTest, DispatchOnComplete_CallsCallback) {
    bool callback_called = false;
    ke_task* task = scheduler.dispatch_on_complete(
        &scheduler,
        [](void*) {},
        nullptr,
        [](ke_task*, void* u) { *static_cast<bool*>(u) = true; },
        &callback_called
    );

    ASSERT_TRUE(callback_called);
    scheduler.wait(&scheduler, task);
}

TEST_F(TaskSchedulerTest, Dispatch_PassesUserData) {
    int value = 0;
    ke_task* task = scheduler.dispatch(&scheduler, [](void* d) {
        *static_cast<int*>(d) = 42;
    }, &value);

    ASSERT_EQ(value, 42);
    scheduler.wait(&scheduler, task);
}

TEST_F(TaskSchedulerTest, Dispatch_NullFunc_DoesNotCrash) {
    ke_task* task = scheduler.dispatch(&scheduler, nullptr, nullptr);
    ASSERT_NE(task, nullptr);
    scheduler.wait(&scheduler, task);
}

TEST_F(TaskSchedulerTest, IsCompleted_NullTask_ReturnsTrue) {
    ASSERT_TRUE(scheduler.is_completed(&scheduler, nullptr));
}

TEST_F(TaskSchedulerTest, MultipleDispatches_AllExecute) {
    std::atomic<int> counter{0};
    for (int i = 0; i < 10; ++i) {
        ke_task* t = scheduler.dispatch(&scheduler, [](void* d) {
            static_cast<std::atomic<int>*>(d)->fetch_add(1);
        }, &counter);
        scheduler.wait(&scheduler, t);
    }
    ASSERT_EQ(counter.load(), 10);
}

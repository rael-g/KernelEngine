#include <gtest/gtest.h>
#include <kernel_engine/threading/threading.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <cstdlib>
#include <cstring>
#include <atomic>
#include <chrono>
#include <thread>

class ThreadingTest : public ::testing::Test {
protected:
    void SetUp() override {
        std::memset(&alloc, 0, sizeof(alloc));
        alloc.alloc = [](ke_allocator*, size_t s, size_t) { return std::malloc(s); };
        alloc.free  = [](ke_allocator*, void* p) { std::free(p); };
    }

    ke_allocator alloc{};
};

// ── Thread Tests ─────────────────────────────────────────────────────────────

TEST_F(ThreadingTest, Thread_CreateAndJoin) {
    std::atomic<bool> executed{false};
    ke_thread_params params = {};
    params.name = "TestThread";
    params.func = [](void* data) {
        auto* flag = static_cast<std::atomic<bool>*>(data);
        *flag = true;
    };
    params.user_data = &executed;

    ke_thread* thread = nullptr;
    ke_result res = ke_thread_std_create(&alloc, &params, &thread);
    ASSERT_EQ(res, KE_OK);
    ASSERT_NE(thread, nullptr);

    thread->join(thread);
    EXPECT_TRUE(executed);

    thread->destroy(thread, &alloc);
}

TEST_F(ThreadingTest, Thread_JoinTimeout) {
    std::atomic<bool> should_exit{false};
    ke_thread_params params = {};
    params.func = [](void* data) {
        auto* flag = static_cast<std::atomic<bool>*>(data);
        while (!*flag) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    };
    params.user_data = &should_exit;

    ke_thread* thread = nullptr;
    ke_result res = ke_thread_std_create(&alloc, &params, &thread);
    ASSERT_EQ(res, KE_OK);

    // Should timeout
    bool joined = thread->join_timeout(thread, 50);
    EXPECT_FALSE(joined);

    // Now signal to exit and join properly
    should_exit = true;
    joined = thread->join_timeout(thread, 1000);
    EXPECT_TRUE(joined);

    thread->destroy(thread, &alloc);
}

TEST_F(ThreadingTest, Thread_TLSName) {
    ke_thread_set_current_name("MainTestThread");
    EXPECT_STREQ(ke_thread_get_current_name(), "MainTestThread");

    std::atomic<bool> name_verified{false};
    ke_thread_params params = {};
    params.name = "WorkerThread";
    params.func = [](void* data) {
        auto* flag = static_cast<std::atomic<bool>*>(data);
        if (std::strcmp(ke_thread_get_current_name(), "WorkerThread") == 0) {
            *flag = true;
        }
    };
    params.user_data = &name_verified;

    ke_thread* thread = nullptr;
    ke_thread_std_create(&alloc, &params, &thread);
    thread->join(thread);
    EXPECT_TRUE(name_verified);
    thread->destroy(thread, &alloc);
}

// ── Semaphore Tests ──────────────────────────────────────────────────────────

TEST_F(ThreadingTest, Semaphore_SignalAndWait) {
    ke_semaphore* sem = nullptr;
    ke_result res = ke_semaphore_std_create(&alloc, 0, &sem);
    ASSERT_EQ(res, KE_OK);
    ASSERT_NE(sem, nullptr);

    std::atomic<bool> wait_completed{false};
    std::thread t([&]() {
        sem->wait(sem);
        wait_completed = true;
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    EXPECT_FALSE(wait_completed);

    sem->signal(sem);
    t.join();
    EXPECT_TRUE(wait_completed);

    sem->destroy(sem, &alloc);
}

TEST_F(ThreadingTest, Semaphore_Counting) {
    ke_semaphore* sem = nullptr;
    ke_semaphore_std_create(&alloc, 2, &sem);

    sem->wait(sem);
    sem->wait(sem);
    
    std::atomic<bool> wait_completed{false};
    std::thread t([&]() {
        sem->wait(sem);
        wait_completed = true;
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    EXPECT_FALSE(wait_completed);

    sem->signal(sem);
    t.join();
    EXPECT_TRUE(wait_completed);

    sem->destroy(sem, &alloc);
}

// ── FrameSync Tests ──────────────────────────────────────────────────────────

TEST_F(ThreadingTest, FrameSync_Handoff) {
    ke_frame_sync* sync = nullptr;
    // 2 buffers, small capacities
    ke_result res = ke_frame_sync_std_create(&alloc, 2, 10, 10, 10, &sync);
    ASSERT_EQ(res, KE_OK);
    ASSERT_NE(sync, nullptr);

    // Sim thread perspective
    ke_frame_packet* packet_w = sync->begin_write(sync);
    ASSERT_NE(packet_w, nullptr);
    packet_w->frame_number = 42;
    sync->end_write(sync);

    // Render thread perspective
    ke_frame_packet* packet_r = sync->begin_read(sync);
    ASSERT_NE(packet_r, nullptr);
    EXPECT_EQ(packet_r->frame_number, 42);
    sync->end_read(sync);

    sync->destroy(sync, &alloc);
}

TEST_F(ThreadingTest, FrameSync_Blocking) {
    ke_frame_sync* sync = nullptr;
    ke_frame_sync_std_create(&alloc, 2, 10, 10, 10, &sync);

    // Fill both buffers
    sync->begin_write(sync);
    sync->end_write(sync);
    sync->begin_write(sync);
    sync->end_write(sync);

    std::atomic<bool> write_completed{false};
    std::thread t([&]() {
        sync->begin_write(sync);
        write_completed = true;
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    EXPECT_FALSE(write_completed);

    // Read one buffer to unblock
    ke_frame_packet* packet = sync->begin_read(sync);
    sync->end_read(sync);
    
    t.join();
    EXPECT_TRUE(write_completed);

    sync->destroy(sync, &alloc);
}

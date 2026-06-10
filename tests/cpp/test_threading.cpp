#include <gtest/gtest.h>
#include <kernel_engine/threading/threading.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <thread>

// Only ke_frame_sync remains in the threading plugin. The ke_thread and
// ke_semaphore vtables were deleted (judged thin stdlib wrappers; host
// languages own thread spawning + sync primitives directly).

class ThreadingTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        std::memset(&alloc, 0, sizeof(alloc));
        alloc.alloc = [](ke_allocator *, size_t s, size_t) { return std::malloc(s); };
        alloc.free  = [](ke_allocator *, void *p) { std::free(p); };
    }

    ke_allocator alloc{};
};

TEST_F(ThreadingTest, FrameSync_Handoff)
{
    ke_frame_sync *sync = nullptr;
    ke_result      res  = ke_frame_sync_std_create(&alloc, 2, 10, 10, 10, &sync);
    ASSERT_EQ(res, KE_OK);
    ASSERT_NE(sync, nullptr);

    ke_frame_packet *packet_w = sync->begin_write(sync);
    ASSERT_NE(packet_w, nullptr);
    packet_w->frame_number = 42;
    sync->end_write(sync);

    ke_frame_packet *packet_r = sync->begin_read(sync);
    ASSERT_NE(packet_r, nullptr);
    EXPECT_EQ(packet_r->frame_number, 42);
    sync->end_read(sync);

    sync->destroy(sync, &alloc);
}

TEST_F(ThreadingTest, FrameSync_NullChecks) {
    ke_frame_sync *s = nullptr;
    ke_frame_sync_std_create(&alloc, 2, 10, 10, 10, &s);
    
    ASSERT_EQ(s->begin_write(nullptr), nullptr);
    s->end_write(nullptr);
    ASSERT_EQ(s->begin_read(nullptr), nullptr);
    s->end_read(nullptr);
    
    s->destroy(nullptr, &alloc);
    s->destroy(s, nullptr);
    s->destroy(s, &alloc);
}

TEST(ThreadingInitTest, Create_NullArgs_ReturnsInvalidArgument) {
    ke_allocator a{};
    ke_frame_sync *s = nullptr;
    ASSERT_EQ(ke_frame_sync_std_create(nullptr, 2, 1, 1, 1, &s), KE_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(ke_frame_sync_std_create(&a, 2, 1, 1, 1, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(ThreadingTest, FrameSync_Blocking)
{
    ke_frame_sync *sync = nullptr;
    ke_frame_sync_std_create(&alloc, 2, 1, 1, 1, &sync);

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

    sync->begin_read(sync);
    sync->end_read(sync);

    t.join();
    EXPECT_TRUE(write_completed);

    sync->destroy(sync, &alloc);
}

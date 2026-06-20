#include <gtest/gtest.h>
#include <kernel_engine/threading/threading.h>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <thread>

// Only ke_frame_sync remains in the threading plugin. The ke_thread and
// ke_semaphore vtables were deleted (judged thin stdlib wrappers; host
// languages own thread spawning + sync primitives directly).

TEST(ThreadingTest, FrameSync_Handoff)
{
    ke_frame_sync_handle sync_h = ke_frame_sync_std_create(2, 10, 10, 10, nullptr);
    ASSERT_NE(sync_h.ref, nullptr);
    ke_frame_sync *sync = sync_h.ref;
    ASSERT_NE(sync, nullptr);

    ke_frame_packet *packet_w = sync->begin_write(sync);
    ASSERT_NE(packet_w, nullptr);
    packet_w->frame_number = 42;
    sync->end_write(sync);

    ke_frame_packet *packet_r = sync->begin_read(sync);
    ASSERT_NE(packet_r, nullptr);
    EXPECT_EQ(packet_r->frame_number, 42);
    sync->end_read(sync);

    sync_h.destroy(sync_h.ref);
}

TEST(ThreadingTest, FrameSync_NullChecks) {
    ke_frame_sync_handle s_h = ke_frame_sync_std_create(2, 10, 10, 10, nullptr);
    ke_frame_sync *s = s_h.ref;

    ASSERT_EQ(s->begin_write(nullptr), nullptr);
    s->end_write(nullptr);
    ASSERT_EQ(s->begin_read(nullptr), nullptr);
    s->end_read(nullptr);

    s_h.destroy(nullptr);    // null self safe
    s_h.destroy(s_h.ref);    // real destroy
}

TEST(ThreadingInitTest, Create_ZeroBuffers_ReturnsNull) {
    // buffer_count == 0 is invalid
    ke_frame_sync_handle s = ke_frame_sync_std_create(1, 60, 60, 100, nullptr);
    ASSERT_EQ(s.ref, nullptr);
}

TEST(ThreadingTest, FrameSync_Blocking)
{
    ke_frame_sync_handle sync_h = ke_frame_sync_std_create(2, 1, 1, 1, nullptr);
    ke_frame_sync *sync = sync_h.ref;

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

    sync_h.destroy(sync_h.ref);
}

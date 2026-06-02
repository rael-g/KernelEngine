#include <gtest/gtest.h>
#include <kernel_engine/kernel/dev_platform/dev_platform.h>
#include <thread>
#include <string.h>

TEST(DevPlatformTest, ThreadName_DefaultIsUnknown) {
    // Note: this might fail if another test already set it on this thread.
    // But GTest usually runs on a fresh thread or we can reset it.
    ke_thread_set_current_name("unknown");
    ASSERT_STREQ(ke_thread_get_current_name(), "unknown");
}

TEST(DevPlatformTest, ThreadName_SetAndGet_Works) {
    ke_thread_set_current_name("main_thread");
    ASSERT_STREQ(ke_thread_get_current_name(), "main_thread");
}

TEST(DevPlatformTest, ThreadName_LongName_IsTruncated) {
    const char* long_name = "this_is_a_very_long_thread_name_that_should_be_truncated_at_sixty_three_chars";
    ke_thread_set_current_name(long_name);
    
    const char* result = ke_thread_get_current_name();
    ASSERT_LE(strlen(result), 63);
    ASSERT_EQ(strncmp(result, long_name, 63), 0);
}

TEST(DevPlatformTest, ThreadName_IsNullSafe) {
    ke_thread_set_current_name("before");
    ke_thread_set_current_name(nullptr);
    ASSERT_STREQ(ke_thread_get_current_name(), "before");
}

TEST(DevPlatformTest, ThreadName_IsThreadLocal) {
    ke_thread_set_current_name("thread1");
    
    std::thread t([]() {
        ke_thread_set_current_name("thread2");
        EXPECT_STREQ(ke_thread_get_current_name(), "thread2");
    });
    t.join();
    
    ASSERT_STREQ(ke_thread_get_current_name(), "thread1");
}

TEST(DevPlatformTest, AssertCurrent_DoesNotAbort_WhenNameMatches) {
    ke_thread_set_current_name("expected");
    ke_thread_assert_current("expected");
    SUCCEED();
}

// Note: Testing that it DOES abort is hard without death tests 
// and might be platform dependent if NDEBUG is set.
#ifndef NDEBUG
TEST(DevPlatformTest, AssertCurrent_Aborts_WhenNameMismatches) {
    ke_thread_set_current_name("wrong");
    ASSERT_DEATH(ke_thread_assert_current("expected"), ".*Thread affinity violation.*");
}
#endif

#include <gtest/gtest.h>
#include <kernel_engine/dev_platform/win32/win32_dev_platform.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <cstdlib>

class Win32DevPlatformTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        alloc.alloc = [](ke_allocator*, size_t s, size_t) { return std::malloc(s); };
        alloc.free  = [](ke_allocator*, void* p) { std::free(p); };
    }

    ke_allocator alloc{};
};

TEST_F(Win32DevPlatformTest, Create_ReturnsOk)
{
    ke_dev_platform* platform = nullptr;
    ke_result result = ke_dev_platform_create_win32(&alloc, &platform);
    
    ASSERT_EQ(result, KE_OK);
    ASSERT_NE(platform, nullptr);
    ASSERT_NE(platform->handle, nullptr);
    ASSERT_NE(platform->destroy, nullptr);
    ASSERT_NE(platform->set_thread_name, nullptr);
    
    platform->destroy(platform);
}

TEST_F(Win32DevPlatformTest, SetThreadName_DoesNotCrash)
{
    ke_dev_platform* platform = nullptr;
    ke_dev_platform_create_win32(&alloc, &platform);
    
    platform->set_thread_name(platform, "TestThread");
    
    platform->destroy(platform);
}

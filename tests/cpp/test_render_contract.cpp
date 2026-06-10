#include <gtest/gtest.h>
#include <gpu_types.hpp>
#include <gpu_device.hpp>

using namespace kernel_engine::render;

TEST(RenderContractTest, GpuClearFlags_BitwiseOr) {
    GpuClearFlags flags = GpuClearFlags::Color | GpuClearFlags::Depth;
    EXPECT_TRUE(HasFlag(flags, GpuClearFlags::Color));
    EXPECT_TRUE(HasFlag(flags, GpuClearFlags::Depth));
    EXPECT_FALSE(HasFlag(flags, GpuClearFlags::Stencil));
}

TEST(RenderContractTest, GpuStateFlags_BitwiseOr) {
    GpuStateFlags flags = GpuStateFlags::WriteR | GpuStateFlags::WriteG;
    EXPECT_TRUE(HasFlag(flags, GpuStateFlags::WriteR));
    EXPECT_TRUE(HasFlag(flags, GpuStateFlags::WriteG));
    EXPECT_FALSE(HasFlag(flags, GpuStateFlags::WriteB));
}

TEST(RenderContractTest, GpuStateFlags_Composite) {
    GpuStateFlags flags = GpuStateFlags::WriteRgb;
    EXPECT_TRUE(HasFlag(flags, GpuStateFlags::WriteR));
    EXPECT_TRUE(HasFlag(flags, GpuStateFlags::WriteG));
    EXPECT_TRUE(HasFlag(flags, GpuStateFlags::WriteB));
    EXPECT_FALSE(HasFlag(flags, GpuStateFlags::WriteA));
}

TEST(RenderContractTest, GpuStateFlags_WriteRgba) {
    GpuStateFlags flags = GpuStateFlags::WriteRgba;
    EXPECT_TRUE(HasFlag(flags, GpuStateFlags::WriteR));
    EXPECT_TRUE(HasFlag(flags, GpuStateFlags::WriteG));
    EXPECT_TRUE(HasFlag(flags, GpuStateFlags::WriteB));
    EXPECT_TRUE(HasFlag(flags, GpuStateFlags::WriteA));
}

TEST(RenderContractTest, BgfxFatalException_StoresMessage) {
    BgfxFatalException ex("Boom");
    EXPECT_STREQ(ex.what(), "Boom");
}

#include <render_logging.hpp>

TEST(RenderContractTest, LogErr_HandlesNullLogger) {
    EXPECT_EQ(LogErr(nullptr, KE_ERROR, "T", "C", "D"), KE_ERROR);
}

static void mock_log_impl(ke_logger* self, const ke_log_event* ev) {
    int* called = (int*)self->handle;
    *called = 1;
}

TEST(RenderContractTest, LogErr_CallsLogger) {
    int called = 0;
    ke_logger logger{};
    logger.handle = &called;
    logger.log = mock_log_impl;
    
    LogErr(&logger, KE_ERROR, "T", "C", "D");
    EXPECT_EQ(called, 1);
}

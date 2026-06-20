#include <gtest/gtest.h>
#include <bgfx_gpu_device.hpp>
#include <kernel_engine/threading/thread_name.h>

using namespace kernel_engine::render;
using namespace kernel_engine::render::bgfx;

class BgfxDeviceFullTest : public ::testing::Test {
protected:
    BgfxGpuDevice device;

    void SetUp() override {
        ke_thread_set_current_name("ke.render");
        GpuInitConfig config{};
        config.renderer_type = 0; // NOOP/NULL
        config.width = 100;
        config.height = 100;
        device.Init(config);
    }

    void TearDown() override {
        device.Shutdown();
    }
};

TEST_F(BgfxDeviceFullTest, FrameBuffer_MultipleAttachments) {
    auto t1 = device.CreateTexture2D(64, 64, false, 1, kTexFmtRGBA8, kTexFlagRT, nullptr);
    auto t2 = device.CreateTexture2D(64, 64, false, 1, kTexFmtD16, kTexFlagRT, nullptr);
    GpuTextureHandle handles[2] = {t1, t2};
    
    auto fb = device.CreateFrameBuffer(2, handles, false);
    EXPECT_NE(fb, kGpuInvalidHandle);
    
    auto rt = device.GetTexture(fb, 0);
    EXPECT_EQ(rt, t1);
    
    device.DestroyFrameBuffer(fb);
    device.DestroyTexture(t1);
    device.DestroyTexture(t2);
}

TEST_F(BgfxDeviceFullTest, Compute_Workflow) {
    device.CreateComputeProgram(kGpuInvalidHandle, false);
    
    auto dib = device.CreateDynamicIndexBuffer(1024, 0);
    EXPECT_NE(dib, kGpuInvalidHandle);
    
    uint8_t data[64] = {0};
    auto* mem = device.Copy(data, sizeof(data));
    device.UpdateDynamicIndexBuffer(dib, 0, mem);
    
    device.SetIndexBufferDynamic(dib);
    device.DestroyDynamicIndexBuffer(dib);
}

TEST_F(BgfxDeviceFullTest, Memory_Ref) {
    uint8_t data[16] = {0};
    auto* mem = device.MakeRef(data, sizeof(data));
    EXPECT_NE(mem, nullptr);
}

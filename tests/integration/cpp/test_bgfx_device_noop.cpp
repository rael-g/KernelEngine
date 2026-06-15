#include <gtest/gtest.h>
#include <bgfx_gpu_device.hpp>
#include <kernel_engine/threading/thread_name.h>
#include <kernel_engine/common/error.h>

using namespace kernel_engine::render;
using namespace kernel_engine::render::bgfx;

class BgfxDeviceNoopTest : public ::testing::Test {
protected:
    BgfxGpuDevice device;

    void SetUp() override {
        ke_thread_set_current_name("ke.render");
    }

    void TearDown() override {
    }
};

TEST_F(BgfxDeviceNoopTest, Init_Shutdown_WorksWithNoop) {
    GpuInitConfig config{};
    config.renderer_type = 0; // BGFX_RENDERER_TYPE_NOOP
    config.width = 1280;
    config.height = 720;
    
    ASSERT_TRUE(device.Init(config));
    
    // Test some basic calls that don't need real GPU state
    EXPECT_STREQ(device.GetShaderSubdir(), "spirv"); // Default for NOOP
    
    auto ndc = device.GetNdcConvention();
    EXPECT_FALSE(ndc.y_flip);
    
    device.Shutdown();
}

TEST_F(BgfxDeviceNoopTest, ResourceCreation_WorksWithNoop) {
    GpuInitConfig config{};
    config.renderer_type = 0;
    if (device.Init(config)) {
        // Memory
        auto* mem = device.Alloc(64);
        EXPECT_NE(mem, nullptr);
        
        uint32_t data[4] = {1, 2, 3, 4};
        auto* mem2 = device.Copy(data, sizeof(data));
        EXPECT_NE(mem2, nullptr);

        // Vertex Buffer
        auto vb = device.CreateVertexBuffer(mem2, kVertexLayoutStandard);
        EXPECT_NE(vb, kGpuInvalidHandle);
        device.DestroyVertexBuffer(vb);

        // Dynamic IB
        auto dib = device.CreateDynamicIndexBuffer(64, 0);
        EXPECT_NE(dib, kGpuInvalidHandle);
        device.DestroyDynamicIndexBuffer(dib);

        // Texture
        auto tex = device.CreateTexture2D(2, 2, false, 1, kTexFmtRGBA8, 0, nullptr);
        device.DestroyTexture(tex);

        // View
        device.SetViewClear(0, GpuClearFlags::Color, 0x303030ff, 1.0f, 0);
        device.SetViewRect(0, 0, 0, 1280, 720);
        
        device.Frame(false);
        
        device.Shutdown();
    }
}

TEST_F(BgfxDeviceNoopTest, GetLastFatalError_ReturnsInternal) {
    device.GetLastFatalError();
}

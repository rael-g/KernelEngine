#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <core_renderer.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/render/frame_packet.h>
#include <kernel_engine/render/render.h>
#include "mocks.hpp"

using namespace kernel_engine::render::bgfx;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

class BgfxRenderTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        gpu_mock = new NiceMock<MockGpuDevice>();
        shader_provider_mock = new NiceMock<MockShaderProvider>();

        GpuRendererParams params{};
        renderer = std::unique_ptr<CoreRenderer>(new CoreRenderer(params));
        
        renderer->SetGpuDevice(gpu_mock);
        renderer->SetShaderProvider(shader_provider_mock);
        renderer->OnInitialize();
    }

    void TearDown() override
    {
        renderer->OnShutdown();
        renderer.reset();
        delete shader_provider_mock;
        delete gpu_mock;
    }

    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    NiceMock<MockShaderProvider>* shader_provider_mock = nullptr;
    std::unique_ptr<CoreRenderer> renderer;
};

TEST_F(BgfxRenderTest, SetOrthographic_ReturnsOk)
{
    EXPECT_EQ(renderer->SetOrthographic(true), KE_OK);
}

TEST_F(BgfxRenderTest, ClearColor_ReturnsOk)
{
    EXPECT_EQ(renderer->ClearColor(1.0f, 0.0f, 0.0f, 1.0f), KE_OK);
}

TEST_F(BgfxRenderTest, SubmitPacket_ReturnsOk)
{
    ke_frame_packet packet{};
    packet.draw_count = 0; 
    EXPECT_EQ(renderer->SubmitPacket(&packet), KE_OK);
}

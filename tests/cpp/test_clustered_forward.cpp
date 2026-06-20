#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <clustered_forward.hpp>
#include <lighting_manager.hpp>
#include <render_context.hpp>
#include <gpu_device.hpp>
#include "mocks.hpp"

using namespace kernel_engine::render;
using namespace kernel_engine::render::core;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

class ClusteredForwardTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        clustered = std::make_unique<ClusteredForward>();
        lighting = std::make_unique<LightingManager>();
        gpu_mock = new NiceMock<MockGpuDevice>();
        ctx.gpu = gpu_mock;
        
        shader_provider = new NiceMock<MockShaderProvider>();
        ctx.shader_provider = shader_provider;
    }

    void TearDown() override
    {
        clustered.reset();
        lighting.reset();
        delete gpu_mock;
        delete shader_provider;
    }

    std::unique_ptr<ClusteredForward> clustered;
    std::unique_ptr<LightingManager> lighting;
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    NiceMock<MockShaderProvider>* shader_provider = nullptr;
    RenderContext ctx{};
};

TEST_F(ClusteredForwardTest, SetupClustered_ReturnsOk)
{
    EXPECT_CALL(*gpu_mock, CreateDynamicIndexBuffer(_, _)).WillRepeatedly(Return(GpuDynamicIndexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));
    EXPECT_CALL(*shader_provider, LoadShaderBinary(_, _)).WillOnce(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillOnce(Return(GpuShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateComputeProgram(_, _)).WillOnce(Return(GpuProgramHandle{1}));

    GpuProgramHandle d, c;
    EXPECT_TRUE(clustered->SetupClustered(ctx, d, c));
}

TEST_F(ClusteredForwardTest, SetClusterConfig_UpdatesInternalState)
{
    ke_cluster_config config = { 8, 4, 12, 128, 256 };
    EXPECT_TRUE(clustered->SetClusterConfig(ctx, &config));
}

TEST_F(ClusteredForwardTest, UpdateClusterBounds_CallsGpuMethods)
{
    EXPECT_CALL(*gpu_mock, CreateDynamicIndexBuffer(_, _)).WillRepeatedly(Return(GpuDynamicIndexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));
    EXPECT_CALL(*shader_provider, LoadShaderBinary(_, _)).WillOnce(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillOnce(Return(GpuShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateComputeProgram(_, _)).WillOnce(Return(GpuProgramHandle{1}));

    GpuProgramHandle d, c;
    clustered->SetupClustered(ctx, d, c);
    
    ctx.near_z = 0.1f; ctx.far_z = 100.0f;
    ctx.last_proj[0] = 1.0f; ctx.last_proj[5] = 1.0f;

    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillOnce(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, UpdateDynamicIndexBuffer(_, _, _)).Times(1);

    clustered->UpdateClusterBounds(ctx);
}

TEST_F(ClusteredForwardTest, DispatchLightCull_CallsGpuDispatch_ForBothTypes)
{
    EXPECT_CALL(*gpu_mock, CreateDynamicIndexBuffer(_, _)).WillRepeatedly(Return(GpuDynamicIndexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));
    EXPECT_CALL(*shader_provider, LoadShaderBinary(_, _)).WillOnce(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillOnce(Return(GpuShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateComputeProgram(_, _)).WillOnce(Return(GpuProgramHandle{1}));

    GpuProgramHandle d, c;
    clustered->SetupClustered(ctx, d, c);

    ke_point_light pl{};
    lighting->StorePointLights(&pl, 1);
    ke_spot_light sl{};
    lighting->StoreSpotLights(&sl, 1);

    EXPECT_CALL(*gpu_mock, Dispatch(_, _, _, _, _)).Times(1);
    clustered->DispatchLightCull(ctx, *lighting, c);
}

TEST_F(ClusteredForwardTest, BindForSceneRead_CallsGpuSetBuffer)
{
    EXPECT_CALL(*gpu_mock, CreateDynamicIndexBuffer(_, _)).WillRepeatedly(Return(GpuDynamicIndexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));
    EXPECT_CALL(*shader_provider, LoadShaderBinary(_, _)).WillOnce(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillOnce(Return(GpuShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateComputeProgram(_, _)).WillOnce(Return(GpuProgramHandle{1}));

    GpuProgramHandle d, c;
    clustered->SetupClustered(ctx, d, c);

    EXPECT_CALL(*gpu_mock, SetBuffer(_, _, _)).Times(::testing::AtLeast(1));
    clustered->BindForSceneRead(ctx);
}

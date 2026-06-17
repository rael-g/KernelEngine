#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <post_process_pipeline.hpp>
#include <geometry_manager.hpp>
#include <texture_manager.hpp>
#include <render_context.hpp>
#include <gpu_device.hpp>
#include "mocks.hpp"

using namespace kernel_engine::render;
using namespace kernel_engine::render::core;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

class PostProcessPipelineTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        pipeline = std::make_unique<PostProcessPipeline>();
        geom = std::make_unique<GeometryManager>();
        tex = std::make_unique<TextureManager>();
        gpu_mock = new NiceMock<MockGpuDevice>();
        ctx.gpu = gpu_mock;
        
        shader_provider = new NiceMock<MockShaderProvider>();
        ctx.shader_provider = shader_provider;
        
        ctx.view_w = 800;
        ctx.view_h = 600;
    }

    void TearDown() override
    {
        pipeline.reset();
        geom.reset();
        tex.reset();
        delete gpu_mock;
        delete shader_provider;
    }

    std::unique_ptr<PostProcessPipeline> pipeline;
    std::unique_ptr<GeometryManager> geom;
    std::unique_ptr<TextureManager> tex;
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    NiceMock<MockShaderProvider>* shader_provider = nullptr;
    RenderContext ctx{};
};

TEST_F(PostProcessPipelineTest, SetupPostProcess_ReturnsOk_WhenShadersValid)
{
    EXPECT_CALL(*shader_provider, LoadShaderBinary(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillRepeatedly(Return(GpuShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateProgram(_, _, _)).WillRepeatedly(Return(GpuProgramHandle{1}));
    
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillRepeatedly(Return(GpuFrameBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));

    GpuProgramHandle b, bl, t;
    EXPECT_EQ(pipeline->SetupPostProcess(ctx, *geom, b, bl, t), KE_OK);
}

TEST_F(PostProcessPipelineTest, SetTonemapping_Fails_WhenNotInitialized)
{
    EXPECT_EQ(pipeline->SetTonemapping(ctx, true, 1.0f, 2.2f), KE_ERROR);
}

TEST_F(PostProcessPipelineTest, SetBloom_Fails_WhenNotInitialized)
{
    EXPECT_EQ(pipeline->SetBloom(ctx, true, 1.0f, 1.0f), KE_ERROR);
}

TEST_F(PostProcessPipelineTest, SetTonemapping_Twice_IsSafe)
{
    EXPECT_CALL(*shader_provider, LoadShaderBinary(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillRepeatedly(Return(GpuShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateProgram(_, _, _)).WillRepeatedly(Return(GpuProgramHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillRepeatedly(Return(GpuFrameBufferHandle{1}));

    GpuProgramHandle b, bl, t;
    pipeline->SetupPostProcess(ctx, *geom, b, bl, t);

    EXPECT_EQ(pipeline->SetTonemapping(ctx, true, 1.0f, 2.2f), KE_OK);
    EXPECT_EQ(pipeline->SetTonemapping(ctx, false, 1.0f, 2.2f), KE_OK);
}

TEST_F(PostProcessPipelineTest, SetSsao_ReturnsOk_WhenEnabled)
{
    EXPECT_CALL(*shader_provider, LoadShaderBinary(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillRepeatedly(Return(GpuShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateProgram(_, _, _)).WillRepeatedly(Return(GpuProgramHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillRepeatedly(Return(GpuFrameBufferHandle{1}));

    EXPECT_EQ(pipeline->SetSsao(ctx, true, 0.5f, 0.025f, 1.0f), KE_OK);
    EXPECT_TRUE(pipeline->IsSsaoEnabled());
}

TEST_F(PostProcessPipelineTest, SetupPostProcess_ReturnsError_WhenShadersFail)
{
    EXPECT_CALL(*shader_provider, LoadShaderBinary(_, _)).WillRepeatedly(Return(nullptr));
    GpuProgramHandle b, bl, t;
    EXPECT_EQ(pipeline->SetupPostProcess(ctx, *geom, b, bl, t), KE_ERROR);
}

TEST_F(PostProcessPipelineTest, SetupPostProcess_ReturnsError_WhenGpuNull)
{
    ctx.gpu = nullptr;
    GpuProgramHandle b, bl, t;
    EXPECT_EQ(pipeline->SetupPostProcess(ctx, *geom, b, bl, t), KE_ERROR);
}

TEST_F(PostProcessPipelineTest, SubmitPostProcess_NoOp_WhenDisabled)
{
    GpuProgramHandle b{1}, bl{2}, t{3};
    // No calls should be made to gpu_mock for submission
    EXPECT_CALL(*gpu_mock, Submit(_, _, _, _)).Times(0);
    pipeline->SubmitPostProcess(ctx, *geom, *tex, b, bl, t);
}

#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <shadow_pipeline.hpp>
#include <geometry_manager.hpp>
#include <render_context.hpp>
#include <gpu_device.hpp>
#include "mocks.hpp"

using namespace kernel_engine::render;
using namespace kernel_engine::render::core;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

class ShadowPipelineTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        pipeline = std::make_unique<ShadowPipeline>();
        geom = std::make_unique<GeometryManager>();
        gpu_mock = new NiceMock<MockGpuDevice>();
        ctx.gpu = gpu_mock;
    }

    void TearDown() override
    {
        pipeline.reset();
        geom.reset();
        delete gpu_mock;
    }

    std::unique_ptr<ShadowPipeline> pipeline;
    std::unique_ptr<GeometryManager> geom;
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    RenderContext ctx{};
};

TEST_F(ShadowPipelineTest, CreateShadowMap_ReturnsOk)
{
    ke_shadow_map_handle handle;
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, kTexFmtR32F, _, _)).WillOnce(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, kTexFmtD16, _, _)).WillOnce(Return(GpuTextureHandle{2}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(2, _, _)).WillOnce(Return(GpuFrameBufferHandle{3}));

    EXPECT_EQ(pipeline->CreateShadowMap(ctx, 512, 512, &handle), KE_OK);
    EXPECT_EQ(handle.idx, 0);
}

TEST_F(ShadowPipelineTest, BeginShadowPass_CallsGpuMethods)
{
    ke_shadow_map_handle h;
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillOnce(Return(GpuFrameBufferHandle{10}));
    pipeline->CreateShadowMap(ctx, 512, 512, &h);

    ke_mat4 v{}, p{};
    EXPECT_CALL(*gpu_mock, SetViewFrameBuffer(_, GpuFrameBufferHandle{10})).Times(1);
    EXPECT_CALL(*gpu_mock, SetViewRect(_, 0, 0, 512, 512)).Times(1);
    EXPECT_CALL(*gpu_mock, SetViewClear(_, _, _, _, _)).Times(1);
    EXPECT_CALL(*gpu_mock, SetViewTransform(_, _, _)).Times(1);

    EXPECT_EQ(pipeline->BeginShadowPass(ctx, h, &v, &p), KE_OK);
}

TEST_F(ShadowPipelineTest, SubmitMeshShadow_CallsGpuMethods)
{
    ke_mat4 t{};
    GpuProgramHandle prog{1};
    ke_mesh_handle m{0};
    
    ke_vertex v[3]={}; uint16_t i[3]={0,1,2};
    EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillOnce(Return(GpuVertexBufferHandle{100}));
    EXPECT_CALL(*gpu_mock, CreateIndexBuffer(_)).WillOnce(Return(GpuIndexBufferHandle{200}));
    geom->CreateMesh(ctx, v, 3, i, 3, &m);

    EXPECT_CALL(*gpu_mock, SetTransform(_, 1)).Times(1);
    EXPECT_CALL(*gpu_mock, SetVertexBuffer(0, GpuVertexBufferHandle{100})).Times(1);
    EXPECT_CALL(*gpu_mock, SetIndexBufferStatic(GpuIndexBufferHandle{200})).Times(1);
    EXPECT_CALL(*gpu_mock, Submit(_, prog, _, _)).Times(1);

    EXPECT_EQ(pipeline->SubmitMeshShadow(ctx, *geom, prog, m, &t), KE_OK);
}

TEST_F(ShadowPipelineTest, SubmitMeshShadow_ReturnsError_OnInvalidMesh)
{
    ke_mat4 t{};
    ke_mesh_handle m{999}; 
    EXPECT_EQ(pipeline->SubmitMeshShadow(ctx, *geom, {1}, m, &t), KE_ERROR);
}

TEST_F(ShadowPipelineTest, DestroyShadowMap_CallsGpuDestroy)
{
    ke_shadow_map_handle h;
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillOnce(Return(GpuFrameBufferHandle{10}));
    pipeline->CreateShadowMap(ctx, 512, 512, &h);

    EXPECT_CALL(*gpu_mock, DestroyFrameBuffer(GpuFrameBufferHandle{10})).Times(1);
    EXPECT_EQ(pipeline->DestroyShadowMap(ctx, h), KE_OK);
}

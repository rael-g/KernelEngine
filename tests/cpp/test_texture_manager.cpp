#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <texture_manager.hpp>
#include <render_context.hpp>
#include <gpu_device.hpp>
#include "mocks.hpp"

using namespace kernel_engine::render;
using namespace kernel_engine::render::core;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

class TextureManagerTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        manager = std::make_unique<TextureManager>();
        gpu_mock = new NiceMock<MockGpuDevice>();
        ctx.gpu = gpu_mock;
    }

    void TearDown() override
    {
        manager.reset();
        delete gpu_mock;
    }

    std::unique_ptr<TextureManager> manager;
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    RenderContext ctx{};
};

TEST_F(TextureManagerTest, CreateTextureRgba_ReturnsOk)
{
    uint8_t pixels[16] = {};
    ke_texture_handle handle;

    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillOnce(Return(GpuTextureHandle{1}));

    EXPECT_EQ(manager->CreateTextureRgba(ctx, 2, 2, pixels, &handle), KE_OK);
    EXPECT_EQ(handle.idx, 0);
}

TEST_F(TextureManagerTest, CreateCubemapRgba_ReturnsOk)
{
    uint8_t data[64] = {};
    ke_texture_handle handle;

    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateTextureCube(_, _, _, _, _, _)).WillOnce(Return(GpuTextureHandle{5}));

    EXPECT_EQ(manager->CreateCubemapRgba(ctx, 2, data, &handle), KE_OK);
    EXPECT_EQ(handle.idx, 0);
}

TEST_F(TextureManagerTest, DestroyTexture_CallsGpuDestroy)
{
    uint8_t pixels[16] = {};
    ke_texture_handle handle;

    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillOnce(Return(GpuTextureHandle{10}));

    manager->CreateTextureRgba(ctx, 2, 2, pixels, &handle);

    EXPECT_CALL(*gpu_mock, DestroyTexture(GpuTextureHandle{10})).Times(1);
    EXPECT_EQ(manager->DestroyTexture(ctx, handle), KE_OK);
}

TEST_F(TextureManagerTest, CreateTextureRgba_ReturnsInvalidArgument_OnNullPixels)
{
    ke_texture_handle handle;
    EXPECT_EQ(manager->CreateTextureRgba(ctx, 2, 2, nullptr, &handle), KE_ERROR);
}

TEST_F(TextureManagerTest, CreateTextureRgba_ReturnsInvalidArgument_OnNullOut)
{
    uint8_t pixels[16] = {};
    EXPECT_EQ(manager->CreateTextureRgba(ctx, 2, 2, pixels, nullptr), KE_ERROR);
}

TEST_F(TextureManagerTest, CreateTextureRgba_ReturnsInvalidArgument_OnZeroWidth)
{
    uint8_t pixels[16] = {};
    ke_texture_handle handle;
    EXPECT_EQ(manager->CreateTextureRgba(ctx, 0, 2, pixels, &handle), KE_ERROR);
}

TEST_F(TextureManagerTest, CreateTextureRgba_ReturnsInvalidArgument_OnZeroHeight)
{
    uint8_t pixels[16] = {};
    ke_texture_handle handle;
    EXPECT_EQ(manager->CreateTextureRgba(ctx, 2, 0, pixels, &handle), KE_ERROR);
}

TEST_F(TextureManagerTest, CreateTextureRgba_ReturnsError_WhenGpuFails)
{
    uint8_t pixels[16] = {};
    ke_texture_handle handle;

    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillOnce(Return(kGpuInvalidHandle));

    EXPECT_EQ(manager->CreateTextureRgba(ctx, 2, 2, pixels, &handle), KE_ERROR);
}

TEST_F(TextureManagerTest, CreateCubemapRgba_ReturnsInvalidArgument_OnNullData)
{
    ke_texture_handle handle;
    EXPECT_EQ(manager->CreateCubemapRgba(ctx, 2, nullptr, &handle), KE_ERROR);
}

TEST_F(TextureManagerTest, CreateCubemapRgba_ReturnsInvalidArgument_OnZeroSize)
{
    uint8_t data[64] = {};
    ke_texture_handle handle;
    EXPECT_EQ(manager->CreateCubemapRgba(ctx, 0, data, &handle), KE_ERROR);
}

TEST_F(TextureManagerTest, DestroyTexture_ReturnsInvalidArgument_OnOutOfBounds)
{
    EXPECT_EQ(manager->DestroyTexture(ctx, {999}), KE_ERROR);
}

TEST_F(TextureManagerTest, CreateCubemapRgba_ReturnsError_WhenGpuFails)
{
    uint8_t data[64] = {};
    ke_texture_handle handle;
    EXPECT_CALL(*gpu_mock, CreateTextureCube(_, _, _, _, _, _)).WillOnce(Return(kGpuInvalidHandle));
    EXPECT_EQ(manager->CreateCubemapRgba(ctx, 2, data, &handle), KE_ERROR);
}

TEST_F(TextureManagerTest, DestroyTexture_ReturnsError_WhenGpuNull)
{
    ctx.gpu = nullptr;
    EXPECT_EQ(manager->DestroyTexture(ctx, {0}), KE_ERROR);
}

TEST_F(TextureManagerTest, SubmitSkybox_UsesDefaultCube_WhenHandleInvalid)
{
    GpuProgramHandle prog{1};
    GpuVertexBufferHandle vb{2};
    GpuIndexBufferHandle ib{3};
    GpuUniformHandle sampler{4};
    GpuUniformHandle tint{5};
    
    manager->default_cube_tex = GpuTextureHandle{99};

    // Should use handle 99 instead of {888}
    EXPECT_CALL(*gpu_mock, SetTexture(0, sampler, GpuTextureHandle{99}, _)).Times(1);
    EXPECT_CALL(*gpu_mock, Submit(_, prog, _, _)).Times(1);

    EXPECT_EQ(manager->SubmitSkybox(ctx, {888}, prog, vb, ib, sampler, tint), KE_OK);
}

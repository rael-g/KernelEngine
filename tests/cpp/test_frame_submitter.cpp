#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <frame_submitter.hpp>
#include <geometry_manager.hpp>
#include <lighting_manager.hpp>
#include <texture_manager.hpp>
#include <shadow_pipeline.hpp>
#include <render_context.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include "mocks.hpp"

using namespace kernel_engine::render::bgfx;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;
using ::testing::AtLeast;

class FrameSubmitterTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        std::memset(&alloc, 0, sizeof(alloc));
        alloc.alloc = [](ke_allocator*, size_t s, size_t) { return std::malloc(s); };
        alloc.free  = [](ke_allocator*, void* p) { std::free(p); };

        gpu_mock = new NiceMock<MockGpuDevice>();
        ctx.gpu = gpu_mock;
        ctx.allocator = &alloc;

        lighting = std::make_unique<LightingManager>();
        geometry = std::make_unique<GeometryManager>();
        textures = std::make_unique<TextureManager>();
        shadows  = std::make_unique<ShadowPipeline>();
    }

    void TearDown() override
    {
        lighting.reset();
        geometry.reset();
        textures.reset();
        shadows.reset();
        delete gpu_mock;
    }

    ke_allocator alloc{};
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    RenderContext ctx{};
    std::unique_ptr<LightingManager> lighting;
    std::unique_ptr<GeometryManager> geometry;
    std::unique_ptr<TextureManager> textures;
    std::unique_ptr<ShadowPipeline> shadows;
};

TEST_F(FrameSubmitterTest, Submit_CallsSetViewTransform)
{
    ke_frame_packet packet{};
    packet.camera.view.m[0] = 1.0f;
    packet.camera.proj.m[0] = 1.0f;

    EXPECT_CALL(*gpu_mock, SetViewTransform(1, _, _)).Times(1);

    FrameSubmitter::Submit(ctx, packet, *geometry, *lighting, *textures, *shadows, 
                           GpuProgramHandle{1}, GpuProgramHandle{1}, GpuProgramHandle{1}, GpuProgramHandle{1});
}

TEST_F(FrameSubmitterTest, Submit_SetsCameraPositionUniform)
{
    ke_frame_packet packet{};
    packet.camera.pos_x = 5.0f;
    packet.camera.pos_y = 6.0f;
    packet.camera.pos_z = 7.0f;

    EXPECT_CALL(*gpu_mock, SetUniform(_, _, 1)).Times(AtLeast(1));

    FrameSubmitter::Submit(ctx, packet, *geometry, *lighting, *textures, *shadows, 
                           GpuProgramHandle{1}, GpuProgramHandle{1}, GpuProgramHandle{1}, GpuProgramHandle{1});
}

TEST_F(FrameSubmitterTest, Submit_ProcessesDrawCommands)
{
    ke_frame_packet packet{};
    packet.draw_capacity = 1;
    packet.draw_count = 1;
    packet.draw_commands = (ke_draw_command*)malloc(sizeof(ke_draw_command));
    packet.draw_commands[0].mesh_handle = {0};
    packet.draw_commands[0].material_handle = {0};

    ke_material mat{};
    mat.r = mat.g = mat.b = mat.a = 1.0f;
    ke_material_handle mh;
    lighting->CreateMaterial(ctx, *textures, &mat, &mh);

    ke_vertex v{};
    uint16_t i = 0;
    ke_mesh_handle h;
    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillOnce(Return(GpuVertexBufferHandle{10}));
    EXPECT_CALL(*gpu_mock, CreateIndexBuffer(_)).WillOnce(Return(GpuIndexBufferHandle{11}));
    geometry->CreateMesh(ctx, &v, 1, &i, 1, &h);

    EXPECT_CALL(*gpu_mock, Submit(1, GpuProgramHandle{1}, 0, false)).Times(1);

    FrameSubmitter::Submit(ctx, packet, *geometry, *lighting, *textures, *shadows, 
                           GpuProgramHandle{1}, GpuProgramHandle{1}, GpuProgramHandle{1}, GpuProgramHandle{1});

    free(packet.draw_commands);
}

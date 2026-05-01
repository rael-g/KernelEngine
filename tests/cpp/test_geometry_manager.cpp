#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <geometry_manager.hpp>
#include <render_context.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include "mocks.hpp"

using namespace kernel_engine::render::bgfx;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

class GeometryManagerTest : public ::testing::Test
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
        
        manager = std::make_unique<GeometryManager>();
    }

    void TearDown() override
    {
        manager.reset();
        delete gpu_mock;
    }

    ke_allocator alloc{};
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    RenderContext ctx{};
    std::unique_ptr<GeometryManager> manager;
};

// ── CreateMesh Tests ─────────────────────────────────────────────────────────

TEST_F(GeometryManagerTest, CreateMesh_ReturnsOk_WhenValidInput)
{
    ke_vertex verts[3] = {};
    uint16_t idx[3] = {0, 1, 2};
    ke_mesh_handle handle;

    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillOnce(Return(GpuVertexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateIndexBuffer(_)).WillOnce(Return(GpuIndexBufferHandle{1}));

    EXPECT_EQ(manager->CreateMesh(ctx, verts, 3, idx, 3, &handle), KE_OK);
}

TEST_F(GeometryManagerTest, CreateMesh_StoresCorrectIndexCount)
{
    ke_vertex verts[3] = {};
    uint16_t idx[3] = {0, 1, 2};
    ke_mesh_handle handle;

    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillOnce(Return(GpuVertexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateIndexBuffer(_)).WillOnce(Return(GpuIndexBufferHandle{1}));

    manager->CreateMesh(ctx, verts, 3, idx, 3, &handle);
    EXPECT_EQ(manager->GetMeshEntry(handle).index_count, 3);
}

TEST_F(GeometryManagerTest, CreateMesh_ReturnsError_WhenGpuFails)
{
    ke_vertex verts[3] = {};
    uint16_t idx[3] = {0, 1, 2};
    ke_mesh_handle handle;

    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillOnce(Return(kGpuInvalidHandle));

    EXPECT_EQ(manager->CreateMesh(ctx, verts, 3, idx, 3, &handle), KE_ERROR_RENDER);
}

// ── RecordDraw Tests ─────────────────────────────────────────────────────────

TEST_F(GeometryManagerTest, RecordDraw_IncrementsDrawCount)
{
    ke_frame_packet packet{};
    packet.draw_capacity = 10;
    packet.draw_commands = (ke_draw_command*)malloc(sizeof(ke_draw_command) * 10);
    packet.draw_count = 0;
    ke_mat4 transform{};

    manager->RecordDraw(packet, 0, 0, &transform);

    EXPECT_EQ(packet.draw_count, 1);
    free(packet.draw_commands);
}

TEST_F(GeometryManagerTest, RecordDraw_CopiesTransform)
{
    ke_frame_packet packet{};
    packet.draw_capacity = 10;
    packet.draw_commands = (ke_draw_command*)malloc(sizeof(ke_draw_command) * 10);
    packet.draw_count = 0;
    
    ke_mat4 transform{};
    transform.m[0] = 5.0f;

    manager->RecordDraw(packet, 0, 0, &transform);

    EXPECT_FLOAT_EQ(packet.draw_commands[0].transform.m[0], 5.0f);
    free(packet.draw_commands);
}

TEST_F(GeometryManagerTest, RecordDraw_ReturnsError_WhenOutOfMemory)
{
    ke_frame_packet packet{};
    packet.draw_capacity = 1;
    packet.draw_commands = (ke_draw_command*)malloc(sizeof(ke_draw_command) * 1);
    packet.draw_count = 1;
    ke_mat4 transform{};

    EXPECT_EQ(manager->RecordDraw(packet, 0, 0, &transform), KE_ERROR_OUT_OF_MEMORY);
    free(packet.draw_commands);
}

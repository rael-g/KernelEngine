#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <geometry_manager.hpp>
#include <render_context.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/render/frame_packet.h>
#include "mocks.hpp"

using namespace kernel_engine::render;
using namespace kernel_engine::render::core;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

class GeometryManagerTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        gpu_mock = new NiceMock<MockGpuDevice>();
        ctx.gpu = gpu_mock;

        manager = std::make_unique<GeometryManager>();
    }

    void TearDown() override
    {
        manager.reset();
        delete gpu_mock;
    }

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

    EXPECT_EQ(manager->CreateMesh(ctx, verts, 3, idx, 3, &handle), KE_ERROR);
}

TEST_F(GeometryManagerTest, CreateMesh_ReturnsInvalidArgument_OnNullVerts)
{
    uint16_t idx[3] = {0, 1, 2};
    ke_mesh_handle handle;
    EXPECT_EQ(manager->CreateMesh(ctx, nullptr, 3, idx, 3, &handle), KE_ERROR);
}

TEST_F(GeometryManagerTest, CreateMesh_ReturnsInvalidArgument_OnNullOut)
{
    ke_vertex verts[3] = {};
    uint16_t idx[3] = {0, 1, 2};
    EXPECT_EQ(manager->CreateMesh(ctx, verts, 3, idx, 3, nullptr), KE_ERROR);
}

TEST_F(GeometryManagerTest, CreateMesh_ReturnsInvalidArgument_OnZeroIndexCount)
{
    ke_vertex verts[3] = {};
    uint16_t idx[3] = {0, 1, 2};
    ke_mesh_handle handle;
    EXPECT_EQ(manager->CreateMesh(ctx, verts, 3, idx, 0, &handle), KE_ERROR);
}

TEST_F(GeometryManagerTest, CreateMesh_ReturnsInvalidArgument_OnNullIndices)
{
    ke_vertex verts[3] = {};
    ke_mesh_handle handle;
    EXPECT_EQ(manager->CreateMesh(ctx, verts, 3, nullptr, 3, &handle), KE_ERROR);
}

// ── DestroyMesh Tests ─────────────────────────────────────────────────────────

TEST_F(GeometryManagerTest, DestroyMesh_CallsGpuDestroy)
{
    ke_vertex verts[3] = {};
    uint16_t idx[3] = {0, 1, 2};
    ke_mesh_handle handle;

    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
    EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillOnce(Return(GpuVertexBufferHandle{10}));
    EXPECT_CALL(*gpu_mock, CreateIndexBuffer(_)).WillOnce(Return(GpuIndexBufferHandle{20}));

    manager->CreateMesh(ctx, verts, 3, idx, 3, &handle);

    EXPECT_CALL(*gpu_mock, DestroyVertexBuffer(GpuVertexBufferHandle{10})).Times(1);
    EXPECT_CALL(*gpu_mock, DestroyIndexBuffer(GpuIndexBufferHandle{20})).Times(1);

    EXPECT_EQ(manager->DestroyMesh(ctx, handle), KE_OK);
}

TEST_F(GeometryManagerTest, DestroyMesh_ReturnsInvalidArgument_OnInvalidHandle)
{
    EXPECT_EQ(manager->DestroyMesh(ctx, {999}), KE_ERROR);
}

// ── RecordDraw Tests ─────────────────────────────────────────────────────────

TEST_F(GeometryManagerTest, RecordDraw_IncrementsDrawCount)
{
    ke_frame_packet packet{};
    packet.draw_capacity = 10;
    packet.draw_commands = (ke_draw_command*)malloc(sizeof(ke_draw_command) * 10);
    packet.draw_count = 0;
    ke_mat4 transform{};

    manager->RecordDraw(packet, {0}, {0}, &transform);

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

    manager->RecordDraw(packet, {0}, {0}, &transform);

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

    EXPECT_EQ(manager->RecordDraw(packet, {0}, {0}, &transform), KE_ERROR);
    free(packet.draw_commands);
}

TEST_F(GeometryManagerTest, RecordDraw_ReturnsInvalidArgument_OnNullTransform)
{
    ke_frame_packet packet{};
    EXPECT_EQ(manager->RecordDraw(packet, {0}, {0}, nullptr), KE_ERROR);
}

// ── GetMeshEntry Tests ───────────────────────────────────────────────────────

TEST_F(GeometryManagerTest, CreateMesh_ReturnsError_WhenGpuNull)
{
    ke_vertex verts[3] = {};
    uint16_t idx[3] = {0, 1, 2};
    ke_mesh_handle handle;
    ctx.gpu = nullptr;
    EXPECT_EQ(manager->CreateMesh(ctx, verts, 3, idx, 3, &handle), KE_ERROR);
}

TEST_F(GeometryManagerTest, DestroyMesh_ReturnsError_WhenGpuNull)
{
    ctx.gpu = nullptr;
    EXPECT_EQ(manager->DestroyMesh(ctx, {0}), KE_ERROR);
}

TEST_F(GeometryManagerTest, RecordDraw_ReturnsError_OnExceedingCapacity)
{
    ke_frame_packet packet{};
    packet.draw_capacity = 1;
    packet.draw_commands = (ke_draw_command*)malloc(sizeof(ke_draw_command) * 1);
    packet.draw_count = 1;
    
    ke_mat4 trans{};
    EXPECT_EQ(manager->RecordDraw(packet, {0}, {0}, &trans), KE_ERROR);
    
    free(packet.draw_commands);
}

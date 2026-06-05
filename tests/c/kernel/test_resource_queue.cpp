#include <gtest/gtest.h>
#include <kernel_engine/framework/resource_queue.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/render/render.h>

#include <atomic>
#include <cstring>
#include <thread>

// ── Mock renderer ────────────────────────────────────────────────────────────
//
// Implements just the ke_render slots the queue calls during drain. Every
// create_* returns a fresh handle from a counter; every destroy logs the
// handle so tests can verify dispatch.

struct MockRenderer
{
    ke_render api{};
    std::atomic<uint32_t> next_handle{1};
    int  create_mesh_count = 0;
    int  destroy_mesh_count = 0;
    int  create_texture_count = 0;
    int  create_cubemap_count = 0;
    int  create_material_count = 0;
    int  create_shadow_count = 0;
    uint32_t last_destroyed = 0;

    // Capture the last create_mesh payload for assertions.
    uint32_t last_mesh_vertex_count = 0;
    uint32_t last_mesh_index_count  = 0;
    uint32_t last_texture_width     = 0;
    uint32_t last_texture_height    = 0;
};

static ke_result Mock_CreateMesh(ke_render *self, const ke_vertex *, uint32_t vc,
                                  const uint16_t *, uint32_t ic, ke_mesh_handle *out)
{
    auto *m = static_cast<MockRenderer *>(self->handle);
    m->create_mesh_count++;
    m->last_mesh_vertex_count = vc;
    m->last_mesh_index_count  = ic;
    out->idx = m->next_handle++;
    return KE_OK;
}

static ke_result Mock_DestroyMesh(ke_render *self, ke_mesh_handle h)
{
    auto *m = static_cast<MockRenderer *>(self->handle);
    m->destroy_mesh_count++;
    m->last_destroyed = h.idx;
    return KE_OK;
}

static ke_result Mock_CreateTexture(ke_render *self, uint32_t w, uint32_t h,
                                     const uint8_t *, ke_texture_handle *out)
{
    auto *m = static_cast<MockRenderer *>(self->handle);
    m->create_texture_count++;
    m->last_texture_width  = w;
    m->last_texture_height = h;
    out->idx = m->next_handle++;
    return KE_OK;
}

static ke_result Mock_CreateCubemap(ke_render *self, uint32_t,
                                     const uint8_t *, ke_texture_handle *out)
{
    auto *m = static_cast<MockRenderer *>(self->handle);
    m->create_cubemap_count++;
    out->idx = m->next_handle++;
    return KE_OK;
}

static ke_result Mock_CreateMaterial(ke_render *self, const ke_material *,
                                      ke_material_handle *out)
{
    auto *m = static_cast<MockRenderer *>(self->handle);
    m->create_material_count++;
    out->idx = m->next_handle++;
    return KE_OK;
}

static ke_result Mock_CreateShadow(ke_render *self, uint32_t, uint32_t,
                                    ke_shadow_map_handle *out)
{
    auto *m = static_cast<MockRenderer *>(self->handle);
    m->create_shadow_count++;
    out->idx = m->next_handle++;
    return KE_OK;
}

static void InitMock(MockRenderer &m)
{
    m.api.handle              = &m;
    m.api.create_mesh         = Mock_CreateMesh;
    m.api.destroy_mesh        = Mock_DestroyMesh;
    m.api.create_texture_rgba = Mock_CreateTexture;
    m.api.create_cubemap_rgba = Mock_CreateCubemap;
    m.api.create_material     = Mock_CreateMaterial;
    m.api.create_shadow_map   = Mock_CreateShadow;
    m.api.destroy_texture     = [](ke_render *, ke_texture_handle) { return KE_OK; };
    m.api.destroy_material    = [](ke_render *, ke_material_handle) { return KE_OK; };
    m.api.destroy_shadow_map  = [](ke_render *, ke_shadow_map_handle) { return KE_OK; };
}

// ── Fixture ──────────────────────────────────────────────────────────────────

class ResourceQueueTest : public ::testing::Test
{
protected:
    ke_allocator      *alloc = nullptr;
    ke_resource_queue *queue = nullptr;
    MockRenderer       renderer;

    void SetUp() override
    {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ASSERT_EQ(ke_resource_queue_create(alloc, &queue), KE_OK);
        InitMock(renderer);
    }

    void TearDown() override
    {
        if (queue) queue->destroy(queue);
    }
};

// ── Submit + drain round-trip ────────────────────────────────────────────────

TEST_F(ResourceQueueTest, Submit_CreateMesh_FutureCompletesWithHandle)
{
    ke_vertex v{0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1};
    uint16_t  i = 0;
    ke_resource_command cmd{};
    cmd.kind = KE_RESOURCE_CMD_CREATE_MESH;
    cmd.u.create_mesh.vertices     = &v;
    cmd.u.create_mesh.vertex_count = 1;
    cmd.u.create_mesh.indices      = &i;
    cmd.u.create_mesh.index_count  = 1;

    ke_resource_future *fut = nullptr;
    ASSERT_EQ(queue->submit(queue, &cmd, &fut), KE_OK);
    ASSERT_NE(fut, nullptr);

    EXPECT_EQ(queue->drain(queue, &renderer.api, 0), 1u);
    EXPECT_EQ(ke_resource_future_wait(fut, 1000), KE_OK);
    EXPECT_EQ(ke_resource_future_get_handle(fut), 1u);
    EXPECT_EQ(renderer.create_mesh_count, 1);
    EXPECT_EQ(renderer.last_mesh_vertex_count, 1u);
    EXPECT_EQ(renderer.last_mesh_index_count,  1u);
    ke_resource_future_release(fut);
}

TEST_F(ResourceQueueTest, Submit_PayloadIsCopied_CallerCanFreeImmediately)
{
    auto *v_local = new ke_vertex{1, 2, 3, 0, 1, 0, 0, 0, 1, 0, 0, 1};
    auto *i_local = new uint16_t(42);
    ke_resource_command cmd{};
    cmd.kind = KE_RESOURCE_CMD_CREATE_MESH;
    cmd.u.create_mesh.vertices     = v_local;
    cmd.u.create_mesh.vertex_count = 1;
    cmd.u.create_mesh.indices      = i_local;
    cmd.u.create_mesh.index_count  = 1;

    ke_resource_future *fut = nullptr;
    ASSERT_EQ(queue->submit(queue, &cmd, &fut), KE_OK);
    // Caller frees its own buffers right after submit returns — queue must have copied.
    delete v_local;
    delete i_local;

    EXPECT_EQ(queue->drain(queue, &renderer.api, 0), 1u);
    EXPECT_EQ(ke_resource_future_wait(fut, 1000), KE_OK);
    EXPECT_EQ(renderer.last_mesh_vertex_count, 1u);
    ke_resource_future_release(fut);
}

TEST_F(ResourceQueueTest, Submit_DestroyCommand_FireAndForget)
{
    ke_resource_command cmd{};
    cmd.kind = KE_RESOURCE_CMD_DESTROY_MESH;
    cmd.u.destroy.handle = 7;
    EXPECT_EQ(queue->submit(queue, &cmd, nullptr), KE_OK);

    EXPECT_EQ(queue->drain(queue, &renderer.api, 0), 1u);
    EXPECT_EQ(renderer.destroy_mesh_count, 1);
    EXPECT_EQ(renderer.last_destroyed, 7u);
}

TEST_F(ResourceQueueTest, Drain_RespectsMaxCount)
{
    ke_resource_command cmd{};
    cmd.kind = KE_RESOURCE_CMD_DESTROY_MESH;
    cmd.u.destroy.handle = 1;
    for (int i = 0; i < 5; ++i) ASSERT_EQ(queue->submit(queue, &cmd, nullptr), KE_OK);

    EXPECT_EQ(queue->drain(queue, &renderer.api, 2), 2u);
    EXPECT_EQ(renderer.destroy_mesh_count, 2);
    EXPECT_EQ(queue->drain(queue, &renderer.api, 0), 3u);
    EXPECT_EQ(renderer.destroy_mesh_count, 5);
}

TEST_F(ResourceQueueTest, Submit_AllCreateKinds_DispatchCorrectly)
{
    auto fire = [&](ke_resource_command_kind kind) {
        ke_resource_command cmd{};
        cmd.kind = kind;
        switch (kind) {
        case KE_RESOURCE_CMD_CREATE_TEXTURE: {
            uint8_t px[4] = {1, 2, 3, 4};
            cmd.u.create_texture.width  = 1;
            cmd.u.create_texture.height = 1;
            cmd.u.create_texture.pixels = px;
            break;
        }
        case KE_RESOURCE_CMD_CREATE_CUBEMAP: {
            uint8_t px[6 * 4] = {};
            cmd.u.create_cubemap.face_size = 1;
            cmd.u.create_cubemap.pixels    = px;
            break;
        }
        case KE_RESOURCE_CMD_CREATE_MATERIAL:
            cmd.u.create_material.material.r = 1.0f;
            break;
        case KE_RESOURCE_CMD_CREATE_SHADOW_MAP:
            cmd.u.create_shadow_map.width  = 512;
            cmd.u.create_shadow_map.height = 512;
            break;
        default: break;
        }
        ke_resource_future *fut = nullptr;
        EXPECT_EQ(queue->submit(queue, &cmd, &fut), KE_OK);
        EXPECT_EQ(queue->drain(queue, &renderer.api, 0), 1u);
        EXPECT_EQ(ke_resource_future_wait(fut, 1000), KE_OK);
        EXPECT_GT(ke_resource_future_get_handle(fut), 0u);
        ke_resource_future_release(fut);
    };
    fire(KE_RESOURCE_CMD_CREATE_TEXTURE);
    fire(KE_RESOURCE_CMD_CREATE_CUBEMAP);
    fire(KE_RESOURCE_CMD_CREATE_MATERIAL);
    fire(KE_RESOURCE_CMD_CREATE_SHADOW_MAP);
    EXPECT_EQ(renderer.create_texture_count, 1);
    EXPECT_EQ(renderer.create_cubemap_count, 1);
    EXPECT_EQ(renderer.create_material_count, 1);
    EXPECT_EQ(renderer.create_shadow_count, 1);
}

TEST_F(ResourceQueueTest, Future_Wait_BlocksUntilDrain)
{
    ke_resource_command cmd{};
    cmd.kind = KE_RESOURCE_CMD_CREATE_SHADOW_MAP;
    cmd.u.create_shadow_map.width  = 1024;
    cmd.u.create_shadow_map.height = 1024;

    ke_resource_future *fut = nullptr;
    ASSERT_EQ(queue->submit(queue, &cmd, &fut), KE_OK);

    // Drain on a separate thread after a small delay.
    std::thread t([&]{
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        queue->drain(queue, &renderer.api, 0);
    });
    EXPECT_EQ(ke_resource_future_wait(fut, 2000), KE_OK);
    t.join();
    EXPECT_GT(ke_resource_future_get_handle(fut), 0u);
    ke_resource_future_release(fut);
}

TEST_F(ResourceQueueTest, Future_Wait_Zero_ReturnsImmediatelyWhenPending)
{
    ke_resource_command cmd{};
    cmd.kind = KE_RESOURCE_CMD_DESTROY_MESH;
    cmd.u.destroy.handle = 1;
    ke_resource_future *fut = nullptr;
    ASSERT_EQ(queue->submit(queue, &cmd, &fut), KE_OK);
    EXPECT_EQ(ke_resource_future_wait(fut, 0), KE_ERROR_INVALID_ARGUMENT);
    queue->drain(queue, &renderer.api, 0);
    EXPECT_EQ(ke_resource_future_wait(fut, 1000), KE_OK);
    ke_resource_future_release(fut);
}

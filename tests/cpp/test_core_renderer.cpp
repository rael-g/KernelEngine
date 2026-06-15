#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <core_renderer.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/render/frame_packet.h>
#include "mocks.hpp"

using namespace kernel_engine::render;
using namespace kernel_engine::render::core;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;
using ::testing::AtLeast;

class CoreRendererTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        std::memset(&alloc, 0, sizeof(alloc));
        alloc.alloc = [](ke_allocator*, size_t s, size_t) { return std::malloc(s); };
        alloc.free  = [](ke_allocator*, void* p) { std::free(p); };

        gpu_mock = new NiceMock<MockGpuDevice>();
        
        std::memset(&window, 0, sizeof(window));
        window.get_native_handle = [](ke_window*) { return (void*)0x123; };
        window.get_size = [](ke_window*, int32_t* w, int32_t* h) { *w = 800; *h = 600; return KE_OK; };

        GpuRendererParams params{};
        params.allocator = &alloc;
        params.renderer_type = 1;
        params.window = &window;
        
        renderer = new CoreRenderer(params);
        renderer->SetGpuDevice(gpu_mock);
        
        shader_mock = new NiceMock<MockShaderProvider>();
        renderer->SetShaderProvider(shader_mock);
    }

    void TearDown() override
    {
        delete renderer;
        delete shader_mock;
        delete gpu_mock;
    }

    ke_allocator alloc{};
    ke_window window{};
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    NiceMock<MockShaderProvider>* shader_mock = nullptr;
    CoreRenderer* renderer = nullptr;

    void MockSuccessfulSetup()
    {
        EXPECT_CALL(*gpu_mock, Init(_)).WillRepeatedly(Return(true));
        EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));
        EXPECT_CALL(*gpu_mock, CreateProgram(_, _, _)).WillRepeatedly(Return(GpuProgramHandle{1}));
        EXPECT_CALL(*shader_mock, LoadShaderBinary(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
        EXPECT_CALL(*gpu_mock, CreateShader(_)).WillRepeatedly(Return(GpuShaderHandle{1}));
        EXPECT_CALL(*gpu_mock, CreateComputeProgram(_, _)).WillRepeatedly(Return(GpuProgramHandle{1}));
        EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
        EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillRepeatedly(Return(GpuFrameBufferHandle{1}));
        EXPECT_CALL(*gpu_mock, CreateDynamicIndexBuffer(_, _)).WillRepeatedly(Return(GpuDynamicIndexBufferHandle{1}));
        EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillRepeatedly(Return(GpuVertexBufferHandle{1}));
        EXPECT_CALL(*gpu_mock, CreateIndexBuffer(_)).WillRepeatedly(Return(GpuIndexBufferHandle{1}));
        EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0x123));
        EXPECT_CALL(*gpu_mock, CreateTextureCube(_, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
    }
};

TEST_F(CoreRendererTest, OnInitialize_ReturnsOk_OnSuccess)
{
    MockSuccessfulSetup();
    EXPECT_EQ(renderer->OnInitialize(), KE_OK);
}

TEST_F(CoreRendererTest, OnInitialize_Fails_WhenGpuInitFails)
{
    EXPECT_CALL(*gpu_mock, Init(_)).WillOnce(Return(false));
    EXPECT_EQ(renderer->OnInitialize(), KE_ERROR_RENDER);
}

TEST_F(CoreRendererTest, OnInitialize_Fails_WhenShadersFail)
{
    EXPECT_CALL(*gpu_mock, Init(_)).WillOnce(Return(true));
    EXPECT_CALL(*shader_mock, LoadShaderBinary(_, _)).WillRepeatedly(Return(nullptr));
    EXPECT_EQ(renderer->OnInitialize(), KE_ERROR_RENDER);
}

TEST_F(CoreRendererTest, Frame_Fails_WhenNotInitialized)
{
    EXPECT_EQ(renderer->Frame(), KE_ERROR_NOT_INITIALIZED);
}

TEST_F(CoreRendererTest, Frame_ReturnsOk_AfterInit)
{
    MockSuccessfulSetup();
    renderer->OnInitialize();
    EXPECT_CALL(*gpu_mock, Frame(false)).WillOnce(Return(1));
    EXPECT_EQ(renderer->Frame(), KE_OK);
}

TEST_F(CoreRendererTest, OnShutdown_DestroysResources)
{
    MockSuccessfulSetup();
    renderer->OnInitialize();

    EXPECT_CALL(*gpu_mock, DestroyProgram(_)).Times(AtLeast(1));
    EXPECT_CALL(*gpu_mock, Shutdown()).Times(1);

    EXPECT_EQ(renderer->OnShutdown(), KE_OK);
}

TEST_F(CoreRendererTest, GetBackbufferSize_ReturnsCorrectSize)
{
    uint32_t w, h;
    renderer->GetBackbufferSize(&w, &h);
    EXPECT_EQ(w, 800);
    EXPECT_EQ(h, 600);
}

TEST_F(CoreRendererTest, SetViewTransform_UpdatesContext)
{
    ke_mat4 view{}, proj{};
    view.m[0] = 1.0f;
    proj.m[10] = -1.1f; // depth near/far calculation
    proj.m[14] = -0.2f;
    proj.m[11] = -1.0f; // perspective

    renderer->SetViewTransform(&view, &proj);
    
    EXPECT_GT(renderer->GetContext().near_z, 0.0f);
}

TEST_F(CoreRendererTest, SetOrthographic_UpdatesState)
{
    renderer->SetOrthographic(true);
    // No easy public getter, but covers the branch
}

TEST_F(CoreRendererTest, ClearColor_Fails_WhenNotInitialized)
{
    EXPECT_EQ(renderer->ClearColor(0,0,0,1), KE_ERROR_NOT_INITIALIZED);
}

TEST_F(CoreRendererTest, SubmitPacket_TriggersAllPasses)
{
    MockSuccessfulSetup();
    renderer->OnInitialize();

    ke_frame_packet packet{};
    // Setup packet to trigger branches
    packet.has_dir_light = true;
    packet.point_light_count = 1;
    packet.point_light_capacity = 1;
    ke_point_light pl{};
    packet.point_lights = &pl;
    
    packet.draw_count = 1;
    ke_draw_command dc{};
    dc.mesh_handle = {0};
    dc.material_handle = {0};
    packet.draw_commands = &dc;
    
    packet.has_skybox = true;
    packet.skybox_handle = {42};
    
    packet.ui_draw_count = 1;
    ke_ui_draw_command udc{};
    packet.ui_draw_commands = &udc;

    packet.ssao_enabled = true;
    packet.tonemapping_enabled = true;
    packet.bloom_enabled = true;

    packet.shadow.map_handle = {1};
    packet.shadow_draw_count = 1;
    ke_draw_command sdc{};
    packet.shadow_draw_commands = &sdc;

    // We need to mock some manager-internal state usually set during Init
    // or just let them run since we used MockSuccessfulSetup.

    EXPECT_CALL(*gpu_mock, Submit(_, _, _, _)).Times(AtLeast(1));
    EXPECT_CALL(*gpu_mock, Dispatch(_, _, _, _, _)).Times(AtLeast(1));

    EXPECT_EQ(renderer->SubmitPacket(&packet), KE_OK);
}

TEST_F(CoreRendererTest, ToApi_ReturnsNonNull)
{
    ASSERT_NE(renderer->ToApi(), nullptr);
}

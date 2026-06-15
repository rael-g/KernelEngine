#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <render_graph_impl.hpp>
#include <core_renderer.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/render/frame_packet.h>
#include "mocks.hpp"

using namespace kernel_engine::render;
using namespace kernel_engine::render::core;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

class RenderGraphImplTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        std::memset(&alloc, 0, sizeof(alloc));
        alloc.alloc = [](ke_allocator*, size_t s, size_t) { return std::malloc(s); };
        alloc.free  = [](ke_allocator*, void* p) { std::free(p); };

        gpu_mock = new NiceMock<MockGpuDevice>();
        
        GpuRendererParams params{};
        params.allocator = &alloc;
        params.renderer_type = 1; // BGFX_RENDERER_TYPE_DIRECT3D11 or similar
        
        renderer = new CoreRenderer(params);
        renderer->SetGpuDevice(gpu_mock);
        graph_impl = new RenderGraphImpl(renderer, &alloc);
    }

    void TearDown() override
    {
        delete graph_impl;
        delete renderer;
        delete gpu_mock;
    }

    ke_allocator alloc{};
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    CoreRenderer* renderer = nullptr;
    RenderGraphImpl* graph_impl = nullptr;
};

TEST_F(RenderGraphImplTest, DeclareResource_ReturnsOk_ForValidDesc)
{
    ke_resource_desc desc{};
    desc.name = "test_tex";
    desc.type = KE_RESOURCE_TYPE_TEXTURE_2D;
    desc.format = KE_FORMAT_RGBA8_UNORM;
    desc.width = 128;
    desc.height = 128;
    
    EXPECT_EQ(graph_impl->DeclareResource(&desc), KE_OK);
}

TEST_F(RenderGraphImplTest, DeclareResource_ReturnsError_OnDuplicate)
{
    ke_resource_desc desc{};
    desc.name = "test_tex";
    desc.type = KE_RESOURCE_TYPE_TEXTURE_2D;
    graph_impl->DeclareResource(&desc);
    EXPECT_EQ(graph_impl->DeclareResource(&desc), KE_ERROR_ALREADY_EXISTS);
}

TEST_F(RenderGraphImplTest, ImportTexture_ReturnsOk)
{
    EXPECT_EQ(graph_impl->ImportTexture("imported", {42}), KE_OK);
}

TEST_F(RenderGraphImplTest, AddPass_ReturnsOk)
{
    ke_render_pass_params p{};
    p.name = "test_pass";
    p.record = [](ke_render_pass_ctx*, void*) {};
    
    EXPECT_EQ(graph_impl->AddPass(&p), KE_OK);
}

TEST_F(RenderGraphImplTest, AddPass_ReturnsError_OnDuplicate)
{
    ke_render_pass_params p{};
    p.name = "test_pass";
    p.record = [](ke_render_pass_ctx*, void*) {};
    graph_impl->AddPass(&p);
    EXPECT_EQ(graph_impl->AddPass(&p), KE_ERROR_ALREADY_EXISTS);
}

TEST_F(RenderGraphImplTest, Compile_ReturnsOk_ForValidGraph)
{
    ke_resource_desc desc{};
    desc.name = "buffer";
    desc.type = KE_RESOURCE_TYPE_TEXTURE_2D;
    desc.format = KE_FORMAT_RGBA8_UNORM;
    desc.width = 64; desc.height = 64;
    graph_impl->DeclareResource(&desc);

    ke_resource_ref write = { "buffer", KE_ACCESS_COLOR_ATTACHMENT };
    ke_render_pass_params p{};
    p.name = "pass";
    p.record = [](ke_render_pass_ctx*, void*) {};
    p.writes = &write;
    p.writes_count = 1;
    graph_impl->AddPass(&p);

    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillOnce(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillOnce(Return(GpuFrameBufferHandle{2}));

    EXPECT_EQ(graph_impl->Compile(), KE_OK);
}

TEST_F(RenderGraphImplTest, Compile_Fails_OnDependencyCycle)
{
    ke_resource_desc r1{}, r2{};
    r1.name = "r1"; r1.type = KE_RESOURCE_TYPE_TEXTURE_2D;
    r2.name = "r2"; r2.type = KE_RESOURCE_TYPE_TEXTURE_2D;
    graph_impl->DeclareResource(&r1);
    graph_impl->DeclareResource(&r2);

    ke_resource_ref r1_read = {"r1", KE_ACCESS_SAMPLED};
    ke_resource_ref r1_write = {"r1", KE_ACCESS_COLOR_ATTACHMENT};
    ke_resource_ref r2_read = {"r2", KE_ACCESS_SAMPLED};
    ke_resource_ref r2_write = {"r2", KE_ACCESS_COLOR_ATTACHMENT};

    ke_render_pass_params p1{};
    p1.name = "p1";
    p1.record = [](auto,auto){};
    p1.reads = &r2_read;
    p1.reads_count = 1;
    p1.writes = &r1_write;
    p1.writes_count = 1;

    ke_render_pass_params p2{};
    p2.name = "p2";
    p2.record = [](auto,auto){};
    p2.reads = &r1_read;
    p2.reads_count = 1;
    p2.writes = &r2_write;
    p2.writes_count = 1;
    
    graph_impl->AddPass(&p1);
    graph_impl->AddPass(&p2);

    EXPECT_EQ(graph_impl->Compile(), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(RenderGraphImplTest, Execute_CallsRecordCallback)
{
    ke_render_pass_params p{};
    p.name = "pass";
    bool called = false;
    p.user = &called;
    p.record = [](ke_render_pass_ctx*, void* u) { *static_cast<bool*>(u) = true; };
    graph_impl->AddPass(&p);

    graph_impl->Execute(nullptr);
    EXPECT_TRUE(called);
}

TEST_F(RenderGraphImplTest, Compile_HandlesDepthTextures)
{
    ke_resource_desc desc{};
    desc.name = "depth";
    desc.type = KE_RESOURCE_TYPE_TEXTURE_2D;
    desc.format = KE_FORMAT_D16;
    desc.width = 64; desc.height = 64;
    graph_impl->DeclareResource(&desc);

    ke_resource_ref write = { "depth", KE_ACCESS_DEPTH_ATTACHMENT };
    ke_render_pass_params p{};
    p.name = "depth_pass";
    p.record = [](auto,auto){};
    p.writes = &write;
    p.writes_count = 1;
    graph_impl->AddPass(&p);

    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, kTexFmtD16, _, _)).WillOnce(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillOnce(Return(GpuFrameBufferHandle{2}));

    EXPECT_EQ(graph_impl->Compile(), KE_OK);
}

TEST_F(RenderGraphImplTest, Execute_NoOp_WhenEmpty)
{
    // Execute on empty graph should return KE_OK and do nothing
    EXPECT_EQ(graph_impl->Execute(nullptr), KE_OK);
}

TEST_F(RenderGraphImplTest, RemovePass_Works)
{
    ke_render_pass_params p{};
    p.name = "to_remove";
    p.record = [](auto,auto){};
    graph_impl->AddPass(&p);
    EXPECT_EQ(graph_impl->RemovePass("to_remove"), KE_OK);
    // Should be able to add it again
    EXPECT_EQ(graph_impl->AddPass(&p), KE_OK);
}

TEST_F(RenderGraphImplTest, RemovePass_ReturnsError_WhenNotFound)
{
    EXPECT_EQ(graph_impl->RemovePass("non_existent"), KE_ERROR_NOT_FOUND);
}

TEST_F(RenderGraphImplTest, AddPass_NullArgs_ReturnsError)
{
    EXPECT_EQ(graph_impl->AddPass(nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(RenderGraphImplTest, DeclareResource_NullArgs_ReturnsError)
{
    EXPECT_EQ(graph_impl->DeclareResource(nullptr), KE_ERROR_INVALID_ARGUMENT);
}

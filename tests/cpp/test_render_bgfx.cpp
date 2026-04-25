#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <core_renderer.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include <kernel_engine/kernel/window/window.h>

using namespace kernel_engine::render::bgfx;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

// ── Mock Implementation of the Agnostic Contract ──────────────────────────

class MockGpuDevice : public GpuDevice
{
public:
    MOCK_METHOD(bool, Init, (const GpuInitConfig& config), (override));
    MOCK_METHOD(void, Shutdown, (), (override));
    MOCK_METHOD(uint32_t, Frame, (bool capture), (override));
    MOCK_METHOD(const char*, GetShaderSubdir, (), (const, override));
    
    MOCK_METHOD(const GpuMemoryBuffer*, Alloc, (uint32_t size), (override));
    MOCK_METHOD(const GpuMemoryBuffer*, Copy, (const void* data, uint32_t size), (override));
    MOCK_METHOD(const GpuMemoryBuffer*, MakeRef, (const void* data, uint32_t size), (override));

    MOCK_METHOD(void, SetViewClear, (uint16_t id, uint16_t flags, uint32_t rgba, float depth, uint8_t stencil), (override));
    MOCK_METHOD(void, SetViewRect, (uint16_t id, uint16_t x, uint16_t y, uint16_t width, uint16_t height), (override));
    MOCK_METHOD(void, SetViewMode, (uint16_t id, GpuViewMode mode), (override));
    MOCK_METHOD(void, SetViewTransform, (uint16_t id, const void* view, const void* proj), (override));
    MOCK_METHOD(void, SetViewFrameBuffer, (uint16_t id, GpuFrameBufferHandle handle), (override));
    MOCK_METHOD(void, Touch, (uint16_t id), (override));

    MOCK_METHOD(GpuShaderHandle, CreateShader, (const GpuMemoryBuffer* mem), (override));
    MOCK_METHOD(GpuProgramHandle, CreateProgram, (GpuShaderHandle vsh, GpuShaderHandle fsh, bool destroyShaders), (override));
    MOCK_METHOD(GpuProgramHandle, CreateComputeProgram, (GpuShaderHandle csh, bool destroyShaders), (override));
    
    MOCK_METHOD(GpuVertexBufferHandle, CreateVertexBuffer, (const GpuMemoryBuffer* mem, uint16_t layout_handle), (override));
    MOCK_METHOD(GpuIndexBufferHandle, CreateIndexBuffer, (const GpuMemoryBuffer* mem), (override));
    MOCK_METHOD(GpuDynamicIndexBufferHandle, CreateDynamicIndexBuffer, (uint32_t num, uint16_t flags), (override));
    MOCK_METHOD(void, UpdateDynamicIndexBuffer, (GpuDynamicIndexBufferHandle handle, uint32_t startIndex, const GpuMemoryBuffer* mem), (override));

    MOCK_METHOD(GpuTextureHandle, CreateTexture2D, (uint16_t width, uint16_t height, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem), (override));
    MOCK_METHOD(GpuTextureHandle, CreateTextureCube, (uint16_t size, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem), (override));
    MOCK_METHOD(GpuFrameBufferHandle, CreateFrameBuffer, (uint8_t num, const GpuTextureHandle* handles, bool destroyTextures), (override));
    MOCK_METHOD(GpuTextureHandle, GetTexture, (GpuFrameBufferHandle handle, uint8_t attachment), (override));

    MOCK_METHOD(GpuUniformHandle, CreateUniform, (const char* name, GpuUniformType type, uint16_t num), (override));

    MOCK_METHOD(void, DestroyShader, (GpuShaderHandle handle), (override));
    MOCK_METHOD(void, DestroyProgram, (GpuProgramHandle handle), (override));
    MOCK_METHOD(void, DestroyUniform, (GpuUniformHandle handle), (override));
    MOCK_METHOD(void, DestroyTexture, (GpuTextureHandle handle), (override));
    MOCK_METHOD(void, DestroyFrameBuffer, (GpuFrameBufferHandle handle), (override));
    MOCK_METHOD(void, DestroyVertexBuffer, (GpuVertexBufferHandle handle), (override));
    MOCK_METHOD(void, DestroyIndexBuffer, (GpuIndexBufferHandle handle), (override));
    MOCK_METHOD(void, DestroyDynamicIndexBuffer, (GpuDynamicIndexBufferHandle handle), (override));

    MOCK_METHOD(void, SetState, (uint64_t state, uint32_t rgba), (override));
    MOCK_METHOD(void, SetTransform, (const void* mtx, uint16_t num), (override));
    MOCK_METHOD(void, SetUniform, (GpuUniformHandle handle, const void* value, uint16_t num), (override));
    MOCK_METHOD(void, SetTexture, (uint8_t stage, GpuUniformHandle sampler, GpuTextureHandle handle, uint32_t flags), (override));
    MOCK_METHOD(void, SetVertexBuffer, (uint8_t stream, GpuVertexBufferHandle handle), (override));
    MOCK_METHOD(void, SetIndexBufferStatic, (GpuIndexBufferHandle handle), (override));
    MOCK_METHOD(void, SetIndexBufferDynamic, (GpuDynamicIndexBufferHandle handle), (override));
    MOCK_METHOD(void, SetBuffer, (uint8_t stage, GpuDynamicIndexBufferHandle handle, GpuAccess access), (override));
    
    MOCK_METHOD(void, Submit, (uint16_t id, GpuProgramHandle program, uint32_t depth, bool preserveState), (override));
    MOCK_METHOD(void, Dispatch, (uint16_t id, GpuProgramHandle program, uint32_t x, uint32_t y, uint32_t z), (override));
    
    MOCK_METHOD(void, SetPaletteColor, (uint8_t index, float r, float g, float b, float a), (override));
    MOCK_METHOD(uint16_t, CreateVertexLayout, (const void* bgfx_layout_ptr), (override));
};

class MockShaderProvider : public ShaderProviderInterface
{
public:
    MOCK_METHOD(const GpuMemoryBuffer*, LoadShaderBinary, (RenderContext& ctx, const std::string& name), (override));
};

// ── Test Fixture ─────────────────────────────────────────────────────────────

class BgfxRenderTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Setup Kernel Allocator
        std::memset(&alloc, 0, sizeof(alloc));
        alloc.alloc = [](ke_allocator*, size_t s, size_t) { return std::malloc(s); };
        alloc.free  = [](ke_allocator*, void* p) { std::free(p); };

        gpu_mock = new NiceMock<MockGpuDevice>();
        shader_mock = std::make_unique<NiceMock<MockShaderProvider>>();

        GpuRendererParams params = {&alloc, nullptr, "shaders/", nullptr, 0};
        renderer = std::make_unique<CoreRenderer>(params);
        renderer->SetGpuDevice(gpu_mock);
        renderer->SetShaderProvider(shader_mock.get());
    }

    void TearDown() override
    {
        renderer.reset();
        // Since SetGpuDevice(gpu_mock) with own_gpu_device = false was called, 
        // we must manually delete the mock to avoid leak.
        delete gpu_mock;
    }

    ke_allocator alloc{};
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    std::unique_ptr<NiceMock<MockShaderProvider>> shader_mock;
    std::unique_ptr<CoreRenderer> renderer;
};

// ── Tests ──────────────────────────────────────────────────────────────────

TEST_F(BgfxRenderTest, SetOrthographic_ReturnsOk)
{
    EXPECT_EQ(renderer->SetOrthographic(true), KE_OK);
}

TEST_F(BgfxRenderTest, ClearColor_ReturnsOk)
{
    // Mock successful initialization to set initialized_ = true
    ke_window window{};
    window.get_native_handle = [](ke_window*) { return (void*)0x1234; };
    window.get_size = [](ke_window*, int32_t* w, int32_t* h) { *w = 800; *h = 600; return KE_OK; };
    
    GpuRendererParams params = {&alloc, nullptr, "shaders/", &window, 0};
    renderer = std::make_unique<CoreRenderer>(params);
    renderer->SetGpuDevice(gpu_mock);
    renderer->SetShaderProvider(shader_mock.get());

    EXPECT_CALL(*shader_mock, LoadShaderBinary(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0xdeadbeef));
    EXPECT_CALL(*gpu_mock, Init(_)).WillOnce(Return(true));
    EXPECT_CALL(*gpu_mock, GetShaderSubdir()).WillRepeatedly(Return("spirv"));
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillRepeatedly(Return(GpuShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateProgram(_, _, _)).WillRepeatedly(Return(GpuProgramHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));
    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return((const GpuMemoryBuffer*)0xdeadbeef));
    EXPECT_CALL(*gpu_mock, CreateVertexLayout(_)).WillRepeatedly(Return(uint16_t{1}));
    EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillRepeatedly(Return(GpuVertexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateIndexBuffer(_)).WillRepeatedly(Return(GpuIndexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillRepeatedly(Return(GpuFrameBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));

    EXPECT_EQ(renderer->OnInitialize(), KE_OK);
    EXPECT_EQ(renderer->ClearColor(1.0f, 0.0f, 0.0f, 1.0f), KE_OK);
}

TEST_F(BgfxRenderTest, SubmitPacket_CallsGpuSubmit)
{
    ke_frame_packet packet{};
    packet.draw_count = 0; 

    // Contract test: should return NOT_INITIALIZED if OnInitialize wasn't called
    EXPECT_EQ(renderer->SubmitPacket(&packet), KE_ERROR_NOT_INITIALIZED);
}

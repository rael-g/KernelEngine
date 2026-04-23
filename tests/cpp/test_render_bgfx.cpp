#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <bgfx_renderer.hpp>
#include <shader_provider.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/window/window.h>
#include <memory>
#include <vector>

using namespace kernel_engine::render::bgfx;
using ::testing::Return;
using ::testing::_;
using ::testing::NiceMock;
using ::testing::AtLeast;

// ── Professional Mocks ────────────────────────────────────────────────────

class MockGpuDevice : public GpuDeviceInterface {
public:
    MOCK_METHOD(bool, Init, (const ::bgfx::Init&), (override));
    MOCK_METHOD(void, Shutdown, (), (override));
    MOCK_METHOD(uint32_t, Frame, (bool), (override));
    
    MOCK_METHOD(const ::bgfx::Memory*, Alloc, (uint32_t), (override));
    MOCK_METHOD(const ::bgfx::Memory*, Copy, (const void*, uint32_t), (override));
    MOCK_METHOD(const ::bgfx::Memory*, MakeRef, (const void*, uint32_t), (override));

    MOCK_METHOD(void, SetViewClear, (uint16_t, uint16_t, uint32_t, float, uint8_t), (override));
    MOCK_METHOD(void, SetViewRect, (uint16_t, uint16_t, uint16_t, uint16_t, uint16_t), (override));
    MOCK_METHOD(void, SetViewMode, (uint16_t, ::bgfx::ViewMode::Enum), (override));
    MOCK_METHOD(void, SetViewTransform, (uint16_t, const void*, const void*), (override));
    MOCK_METHOD(void, SetViewFrameBuffer, (uint16_t, ::bgfx::FrameBufferHandle), (override));
    MOCK_METHOD(void, Touch, (uint16_t), (override));
    MOCK_METHOD(::bgfx::ShaderHandle, CreateShader, (const ::bgfx::Memory*), (override));
    MOCK_METHOD(::bgfx::ProgramHandle, CreateProgram, (::bgfx::ShaderHandle, ::bgfx::ShaderHandle, bool), (override));
    MOCK_METHOD(::bgfx::ProgramHandle, CreateComputeProgram, (::bgfx::ShaderHandle, bool), (override));
    MOCK_METHOD(::bgfx::VertexBufferHandle, CreateVertexBuffer, (const ::bgfx::Memory*, const ::bgfx::VertexLayout&), (override));
    MOCK_METHOD(::bgfx::IndexBufferHandle, CreateIndexBuffer, (const ::bgfx::Memory*), (override));
    MOCK_METHOD(::bgfx::DynamicIndexBufferHandle, CreateDynamicIndexBuffer, (uint32_t, uint16_t), (override));
    MOCK_METHOD(void, UpdateDynamicIndexBuffer, (::bgfx::DynamicIndexBufferHandle, uint32_t, const ::bgfx::Memory*), (override));
    MOCK_METHOD(::bgfx::TextureHandle, CreateTexture2D, (uint16_t, uint16_t, bool, uint16_t, ::bgfx::TextureFormat::Enum, uint64_t, const ::bgfx::Memory*), (override));
    MOCK_METHOD(::bgfx::TextureHandle, CreateTextureCube, (uint16_t, bool, uint16_t, ::bgfx::TextureFormat::Enum, uint64_t, const ::bgfx::Memory*), (override));
    MOCK_METHOD(::bgfx::FrameBufferHandle, CreateFrameBuffer, (uint8_t, const ::bgfx::TextureHandle*, bool), (override));
    MOCK_METHOD(::bgfx::TextureHandle, GetTexture, (::bgfx::FrameBufferHandle, uint8_t), (override));
    MOCK_METHOD(::bgfx::UniformHandle, CreateUniform, (const char*, ::bgfx::UniformType::Enum, uint16_t), (override));
    MOCK_METHOD(void, Destroy, (::bgfx::ShaderHandle), (override));
    MOCK_METHOD(void, Destroy, (::bgfx::ProgramHandle), (override));
    MOCK_METHOD(void, Destroy, (::bgfx::UniformHandle), (override));
    MOCK_METHOD(void, Destroy, (::bgfx::TextureHandle), (override));
    MOCK_METHOD(void, Destroy, (::bgfx::FrameBufferHandle), (override));
    MOCK_METHOD(void, Destroy, (::bgfx::VertexBufferHandle), (override));
    MOCK_METHOD(void, Destroy, (::bgfx::IndexBufferHandle), (override));
    MOCK_METHOD(void, Destroy, (::bgfx::DynamicIndexBufferHandle), (override));
    MOCK_METHOD(void, SetState, (uint64_t, uint32_t), (override));
    MOCK_METHOD(void, SetTransform, (const void*, uint16_t), (override));
    MOCK_METHOD(void, SetUniform, (::bgfx::UniformHandle, const void*, uint16_t), (override));
    MOCK_METHOD(void, SetTexture, (uint8_t, ::bgfx::UniformHandle, ::bgfx::TextureHandle, uint32_t), (override));
    MOCK_METHOD(void, SetVertexBuffer, (uint8_t, ::bgfx::VertexBufferHandle), (override));
    MOCK_METHOD(void, SetIndexBuffer, (::bgfx::IndexBufferHandle), (override));
    MOCK_METHOD(void, SetIndexBuffer, (::bgfx::DynamicIndexBufferHandle), (override));
    MOCK_METHOD(void, SetBuffer, (uint8_t, ::bgfx::DynamicIndexBufferHandle, ::bgfx::Access::Enum), (override));
    MOCK_METHOD(void, Submit, (uint16_t, ::bgfx::ProgramHandle, uint32_t, bool), (override));
    MOCK_METHOD(void, Dispatch, (uint16_t, ::bgfx::ProgramHandle, uint32_t, uint32_t, uint32_t), (override));
    MOCK_METHOD(void, SetPaletteColor, (uint8_t, float, float, float, float), (override));
};

class MockShaderProvider : public ShaderProviderInterface
{
public:
    MOCK_METHOD(const ::bgfx::Memory*, LoadShaderBinary, (RenderContext& ctx, const std::string& name), (override));
};

// ── Test Suite ────────────────────────────────────────────────────────────

class BgfxRenderTest : public ::testing::Test
{
protected:
    ke_allocator* alloc = nullptr;
    ke_window* window = nullptr;
    ke_logger* logger = nullptr;
    BgfxRenderer* impl = nullptr;
    std::unique_ptr<NiceMock<MockShaderProvider>> shader_mock;
    std::unique_ptr<NiceMock<MockGpuDevice>> gpu_mock;
    
    // Safety buffer for mock memory
    uint8_t dummy_payload[1024];
    alignas(::bgfx::Memory) uint8_t dummy_mem_storage[sizeof(::bgfx::Memory)];
    ::bgfx::Memory* dummy_mem_ptr = nullptr;

    void SetUp() override
    {
        alloc = ke_allocator_malloc_create();
        
        window = static_cast<ke_window*>(calloc(1, sizeof(ke_window)));
        window->get_native_handle = [](ke_window*) -> void* { return (void*)0x1234; };
        window->get_size = [](ke_window*, int32_t* w, int32_t* h) { *w = 800; *h = 600; return KE_OK; };

        logger = static_cast<ke_logger*>(calloc(1, sizeof(ke_logger)));
        logger->log = [](ke_logger*, const ke_log_event*) {};

        ke_render_bgfx_params params = { 
            alloc, 
            logger, 
            nullptr, 
            window, 
            "shaders",
            (uint32_t)::bgfx::RendererType::Noop 
        };
        
        impl = new BgfxRenderer(&params);

        shader_mock = std::make_unique<NiceMock<MockShaderProvider>>();
        gpu_mock    = std::make_unique<NiceMock<MockGpuDevice>>();
        
        impl->SetShaderProvider(shader_mock.get());
        impl->SetGpuDevice(gpu_mock.get());

        // Initialize safety memory
        memset(dummy_payload, 0, sizeof(dummy_payload));
        dummy_mem_ptr = reinterpret_cast<::bgfx::Memory*>(dummy_mem_storage);
        dummy_mem_ptr->data = dummy_payload;
        dummy_mem_ptr->size = sizeof(dummy_payload);
    }

    void TearDown() override
    {
        if (impl) {
            impl->SetShaderProvider(nullptr);
            impl->SetGpuDevice(nullptr);
            delete impl;
        }
        
        if (window) free(window);
        if (logger) free(logger);
        if (alloc) alloc->destroy(alloc);
    }
};

// ── Canonical Tests ───────────────────────────────────────────────────────

TEST(BgfxRenderInitTest, Create_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_render_bgfx_create(nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, SetOrthographic_ReturnsOk) {
    ASSERT_EQ(impl->SetOrthographic(true), KE_OK);
}

TEST_F(BgfxRenderTest, SetCameraPos_ReturnsOk) {
    ASSERT_EQ(impl->SetCameraPos(10.0f, 5.0f, -2.0f), KE_OK);
}

TEST_F(BgfxRenderTest, SetAmbientLight_ReturnsOk) {
    ASSERT_EQ(impl->SetAmbientLight(0.2f, 0.2f, 0.2f), KE_OK);
}

TEST_F(BgfxRenderTest, ClearColor_ReturnsNotInitialized) {
    ASSERT_EQ(impl->ClearColor(1.0f, 0.0f, 0.0f, 1.0f), KE_ERROR_NOT_INITIALIZED);
}

TEST_F(BgfxRenderTest, SetClusterConfig_ReturnsNotInitialized) {
    ke_cluster_config config = { 16, 9, 24, 64, 1024 };
    ASSERT_EQ(impl->SetClusterConfig(&config), KE_ERROR_NOT_INITIALIZED);
}

TEST_F(BgfxRenderTest, OnInitialize_Success)
{
    EXPECT_CALL(*gpu_mock, Init(_)).WillOnce(Return(true));
    EXPECT_CALL(*gpu_mock, Alloc(_)).WillRepeatedly(Return(dummy_mem_ptr));
    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return(dummy_mem_ptr));
    EXPECT_CALL(*gpu_mock, MakeRef(_, _)).WillRepeatedly(Return(dummy_mem_ptr));
    
    EXPECT_CALL(*shader_mock, LoadShaderBinary(_, _))
        .WillRepeatedly(Return(dummy_mem_ptr));

    // Expect resource creations
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillRepeatedly(Return(::bgfx::ShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateProgram(_, _, _)).WillRepeatedly(Return(::bgfx::ProgramHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateComputeProgram(_, _)).WillRepeatedly(Return(::bgfx::ProgramHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(::bgfx::UniformHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillRepeatedly(Return(::bgfx::VertexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateIndexBuffer(_)).WillRepeatedly(Return(::bgfx::IndexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillRepeatedly(Return(::bgfx::TextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateTextureCube(_, _, _, _, _, _)).WillRepeatedly(Return(::bgfx::TextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillRepeatedly(Return(::bgfx::FrameBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, GetTexture(_, _)).WillRepeatedly(Return(::bgfx::TextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateDynamicIndexBuffer(_, _)).WillRepeatedly(Return(::bgfx::DynamicIndexBufferHandle{1}));

    ASSERT_EQ(impl->OnInitialize(), KE_OK);
}

TEST_F(BgfxRenderTest, Frame_FailsWithoutInit) {
    ASSERT_EQ(impl->Frame(), KE_ERROR_NOT_INITIALIZED);
}

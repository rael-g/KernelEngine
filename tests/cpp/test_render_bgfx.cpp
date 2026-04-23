#include <gtest/gtest.h>
#include <gmock/gmock.h>

// Product Header (Entry point)
#include <kernel_engine/render/bgfx/bgfx_render.h>

// Internal Core Headers
#include <core_renderer.hpp>
#include <shader_provider.hpp>
#include <gpu_device.hpp>

// Kernel Headers (Full definitions)
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/window/window.h>

#include <memory>
#include <vector>
#include <cstring>

using namespace kernel_engine::render::bgfx;
using ::testing::Return;
using ::testing::_;
using ::testing::NiceMock;
using ::testing::AtLeast;

// ── Professional HAL Mocks ────────────────────────────────────────────────

class MockGpuDevice : public GpuDeviceInterface {
public:
    MOCK_METHOD(bool, Init, (const GpuInitConfig&), (override));
    MOCK_METHOD(void, Shutdown, (), (override));
    MOCK_METHOD(uint32_t, Frame, (bool), (override));
    
    MOCK_METHOD(const GpuMemoryBuffer*, Alloc, (uint32_t), (override));
    MOCK_METHOD(const GpuMemoryBuffer*, Copy, (const void*, uint32_t), (override));
    MOCK_METHOD(const GpuMemoryBuffer*, MakeRef, (const void*, uint32_t), (override));

    MOCK_METHOD(void, SetViewClear, (uint16_t, uint16_t, uint32_t, float, uint8_t), (override));
    MOCK_METHOD(void, SetViewRect, (uint16_t, uint16_t, uint16_t, uint16_t, uint16_t), (override));
    MOCK_METHOD(void, SetViewMode, (uint16_t, GpuViewMode), (override));
    MOCK_METHOD(void, SetViewTransform, (uint16_t, const void*, const void*), (override));
    MOCK_METHOD(void, SetViewFrameBuffer, (uint16_t, GpuFrameBufferHandle), (override));
    MOCK_METHOD(void, Touch, (uint16_t), (override));

    MOCK_METHOD(GpuShaderHandle, CreateShader, (const GpuMemoryBuffer*), (override));
    MOCK_METHOD(GpuProgramHandle, CreateProgram, (GpuShaderHandle, GpuShaderHandle, bool), (override));
    MOCK_METHOD(GpuProgramHandle, CreateComputeProgram, (GpuShaderHandle, bool), (override));
    
    MOCK_METHOD(GpuVertexBufferHandle, CreateVertexBuffer, (const GpuMemoryBuffer*, uint16_t), (override));
    MOCK_METHOD(GpuIndexBufferHandle, CreateIndexBuffer, (const GpuMemoryBuffer*), (override));
    MOCK_METHOD(GpuDynamicIndexBufferHandle, CreateDynamicIndexBuffer, (uint32_t, uint16_t), (override));
    MOCK_METHOD(void, UpdateDynamicIndexBuffer, (GpuDynamicIndexBufferHandle, uint32_t, const GpuMemoryBuffer*), (override));

    MOCK_METHOD(GpuTextureHandle, CreateTexture2D, (uint16_t, uint16_t, bool, uint16_t, uint32_t, uint64_t, const GpuMemoryBuffer*), (override));
    MOCK_METHOD(GpuTextureHandle, CreateTextureCube, (uint16_t, bool, uint16_t, uint32_t, uint64_t, const GpuMemoryBuffer*), (override));
    MOCK_METHOD(GpuFrameBufferHandle, CreateFrameBuffer, (uint8_t, const GpuTextureHandle*, bool), (override));
    MOCK_METHOD(GpuTextureHandle, GetTexture, (GpuFrameBufferHandle, uint8_t), (override));

    MOCK_METHOD(GpuUniformHandle, CreateUniform, (const char*, GpuUniformType, uint16_t), (override));

    MOCK_METHOD(void, DestroyShader, (GpuShaderHandle), (override));
    MOCK_METHOD(void, DestroyProgram, (GpuProgramHandle), (override));
    MOCK_METHOD(void, DestroyUniform, (GpuUniformHandle), (override));
    MOCK_METHOD(void, DestroyTexture, (GpuTextureHandle), (override));
    MOCK_METHOD(void, DestroyFrameBuffer, (GpuFrameBufferHandle), (override));
    MOCK_METHOD(void, DestroyVertexBuffer, (GpuVertexBufferHandle), (override));
    MOCK_METHOD(void, DestroyIndexBuffer, (GpuIndexBufferHandle), (override));
    MOCK_METHOD(void, DestroyDynamicIndexBuffer, (GpuDynamicIndexBufferHandle), (override));

    MOCK_METHOD(void, SetState, (uint64_t, uint32_t), (override));
    MOCK_METHOD(void, SetTransform, (const void*, uint16_t), (override));
    MOCK_METHOD(void, SetUniform, (GpuUniformHandle, const void*, uint16_t), (override));
    MOCK_METHOD(void, SetTexture, (uint8_t, GpuUniformHandle, GpuTextureHandle, uint32_t), (override));
    MOCK_METHOD(void, SetVertexBuffer, (uint8_t, GpuVertexBufferHandle), (override));
    MOCK_METHOD(void, SetIndexBufferStatic, (GpuIndexBufferHandle), (override));
    MOCK_METHOD(void, SetIndexBufferDynamic, (GpuDynamicIndexBufferHandle), (override));
    MOCK_METHOD(void, SetBuffer, (uint8_t, GpuDynamicIndexBufferHandle, GpuAccess), (override));
    
    MOCK_METHOD(void, Submit, (uint16_t, GpuProgramHandle, uint32_t, bool), (override));
    MOCK_METHOD(void, Dispatch, (uint16_t, GpuProgramHandle, uint32_t, uint32_t, uint32_t), (override));
    
    MOCK_METHOD(void, SetPaletteColor, (uint8_t, float, float, float, float), (override));
    MOCK_METHOD(uint16_t, CreateVertexLayout, (const void*), (override));
};

class MockShaderProvider : public ShaderProviderInterface
{
public:
    MOCK_METHOD(const GpuMemoryBuffer*, LoadShaderBinary, (RenderContext& ctx, const std::string& name), (override));
};

// ── Test Suite ────────────────────────────────────────────────────────────

class BgfxRenderTest : public ::testing::Test
{
protected:
    ::ke_allocator* alloc = nullptr;
    ::ke_window* window = nullptr;
    ::ke_logger* logger = nullptr;
    CoreRenderer* impl = nullptr;
    std::unique_ptr<NiceMock<MockShaderProvider>> shader_mock;
    std::unique_ptr<NiceMock<MockGpuDevice>> gpu_mock;
    
    // Safety buffer for mock memory
    uint8_t dummy_payload[1024];
    GpuMemoryBuffer dummy_mem_struct;

    void SetUp() override
    {
        alloc = ke_allocator_malloc_create();
        
        window = static_cast<::ke_window*>(calloc(1, sizeof(::ke_window)));
        window->get_native_handle = [](::ke_window*) -> void* { return (void*)0x1234; };
        window->get_size = [](::ke_window*, int32_t* w, int32_t* h) { *w = 800; *h = 600; return KE_OK; };

        logger = static_cast<::ke_logger*>(calloc(1, sizeof(::ke_logger)));
        logger->log = [](::ke_logger*, const ke_log_event*) {};

        GpuRendererParams core_params = {
            alloc,
            logger,
            "shaders",
            window,
            (uint32_t)0 // Noop or default
        };

        impl = new CoreRenderer(core_params);

        shader_mock = std::make_unique<NiceMock<MockShaderProvider>>();
        gpu_mock    = std::make_unique<NiceMock<MockGpuDevice>>();
        
        impl->SetShaderProvider(shader_mock.get());
        impl->SetGpuDevice(gpu_mock.get());

        // Initialize safety memory
        memset(dummy_payload, 0, sizeof(dummy_payload));
        dummy_mem_struct.data = dummy_payload;
        dummy_mem_struct.size = sizeof(dummy_payload);
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
    EXPECT_CALL(*gpu_mock, Alloc(_)).WillRepeatedly(Return(&dummy_mem_struct));
    EXPECT_CALL(*gpu_mock, Copy(_, _)).WillRepeatedly(Return(&dummy_mem_struct));
    EXPECT_CALL(*gpu_mock, MakeRef(_, _)).WillRepeatedly(Return(&dummy_mem_struct));
    
    EXPECT_CALL(*shader_mock, LoadShaderBinary(_, _))
        .WillRepeatedly(Return(&dummy_mem_struct));

    // Expect resource creations
    EXPECT_CALL(*gpu_mock, CreateShader(_)).WillRepeatedly(Return(GpuShaderHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateProgram(_, _, _)).WillRepeatedly(Return(GpuProgramHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateComputeProgram(_, _)).WillRepeatedly(Return(GpuProgramHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateUniform(_, _, _)).WillRepeatedly(Return(GpuUniformHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateVertexBuffer(_, _)).WillRepeatedly(Return(GpuVertexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateIndexBuffer(_)).WillRepeatedly(Return(GpuIndexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateTexture2D(_, _, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateTextureCube(_, _, _, _, _, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateFrameBuffer(_, _, _)).WillRepeatedly(Return(GpuFrameBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, GetTexture(_, _)).WillRepeatedly(Return(GpuTextureHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateDynamicIndexBuffer(_, _)).WillRepeatedly(Return(GpuDynamicIndexBufferHandle{1}));
    EXPECT_CALL(*gpu_mock, CreateVertexLayout(_)).WillRepeatedly(Return(uint16_t{1}));

    ASSERT_EQ(impl->OnInitialize(), KE_OK);
}

TEST_F(BgfxRenderTest, Frame_FailsWithoutInit) {
    ASSERT_EQ(impl->Frame(), KE_ERROR_NOT_INITIALIZED);
}

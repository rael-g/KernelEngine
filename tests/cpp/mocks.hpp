#pragma once
#include <gmock/gmock.h>
#include <gpu_device.hpp>
#include <shader_provider.hpp>
#include <render_context.hpp>

namespace kernel_engine::render {

class MockGpuDevice : public GpuDevice
{
public:
    MOCK_METHOD(void, SetLogger, (struct ke_logger* logger), (override));
    MOCK_METHOD(bool, Init, (const GpuInitConfig& config), (override));
    MOCK_METHOD(void, Shutdown, (), (override));
    MOCK_METHOD(uint32_t, Frame, (bool capture), (override));
    MOCK_METHOD(const char*, GetShaderSubdir, (), (const, override));
    MOCK_METHOD(const GpuMemoryBuffer*, Alloc, (uint32_t size), (override));
    MOCK_METHOD(const GpuMemoryBuffer*, Copy, (const void* data, uint32_t size), (override));
    MOCK_METHOD(const GpuMemoryBuffer*, MakeRef, (const void* data, uint32_t size), (override));
    MOCK_METHOD(void, SetViewClear, (uint16_t id, GpuClearFlags flags, uint32_t rgba, float depth, uint8_t stencil), (override));
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
    MOCK_METHOD(void, SetState, (GpuStateFlags state, uint32_t rgba), (override));
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
    MOCK_METHOD(const char*, GetLastFatalError, (), (override));
};

namespace core {

class MockShaderProvider : public ShaderProviderInterface
{
public:
    MOCK_METHOD(const GpuMemoryBuffer*, LoadShaderBinary, (core::RenderContext& ctx, const std::string& name), (override));
};

} // namespace core
} // namespace kernel_engine::render

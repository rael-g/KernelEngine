#pragma once

#include <gpu_device.hpp>

namespace kernel_engine::render::bgfx
{

/**
 * @brief BGFX implementation of the GpuDevice contract.
 */
class BgfxGpuDevice : public GpuDevice
{
public:
    void SetLogger(struct ke_logger* logger) override;

    bool Init(const GpuInitConfig& config) override;
    void Shutdown() override;
    uint32_t Frame(bool capture) override;
    const char* GetShaderSubdir() const override;
    GpuNdcConvention GetNdcConvention() const override;

    const GpuMemoryBuffer* Alloc(uint32_t size) override;
    const GpuMemoryBuffer* Copy(const void* data, uint32_t size) override;
    const GpuMemoryBuffer* MakeRef(const void* data, uint32_t size) override;

    void SetViewClear(uint16_t id, GpuClearFlags flags, uint32_t rgba, float depth, uint8_t stencil) override;
    void SetViewRect(uint16_t id, uint16_t x, uint16_t y, uint16_t width, uint16_t height) override;
    void SetViewMode(uint16_t id, GpuViewMode mode) override;
    void SetViewTransform(uint16_t id, const void* view, const void* proj) override;
    void SetViewFrameBuffer(uint16_t id, GpuFrameBufferHandle handle) override;
    void Touch(uint16_t id) override;

    GpuShaderHandle CreateShader(const GpuMemoryBuffer* mem) override;
    GpuProgramHandle CreateProgram(GpuShaderHandle vsh, GpuShaderHandle fsh, bool destroyShaders) override;
    GpuProgramHandle CreateComputeProgram(GpuShaderHandle csh, bool destroyShaders) override;

    GpuVertexBufferHandle CreateVertexBuffer(const GpuMemoryBuffer* mem, uint16_t layout_handle) override;
    GpuIndexBufferHandle CreateIndexBuffer(const GpuMemoryBuffer* mem) override;
    GpuDynamicIndexBufferHandle CreateDynamicIndexBuffer(uint32_t num, uint16_t flags) override;
    void UpdateDynamicIndexBuffer(GpuDynamicIndexBufferHandle handle, uint32_t startIndex, const GpuMemoryBuffer* mem) override;

    GpuTextureHandle CreateTexture2D(uint16_t width, uint16_t height, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem) override;
    GpuTextureHandle CreateTextureCube(uint16_t size, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem) override;
    GpuFrameBufferHandle CreateFrameBuffer(uint8_t num, const GpuTextureHandle* handles, bool destroyTextures) override;
    GpuTextureHandle GetTexture(GpuFrameBufferHandle handle, uint8_t attachment) override;

    GpuUniformHandle CreateUniform(const char* name, GpuUniformType type, uint16_t num) override;

    void DestroyShader(GpuShaderHandle handle) override;
    void DestroyProgram(GpuProgramHandle handle) override;
    void DestroyUniform(GpuUniformHandle handle) override;
    void DestroyTexture(GpuTextureHandle handle) override;
    void DestroyFrameBuffer(GpuFrameBufferHandle handle) override;
    void DestroyVertexBuffer(GpuVertexBufferHandle handle) override;
    void DestroyIndexBuffer(GpuIndexBufferHandle handle) override;
    void DestroyDynamicIndexBuffer(GpuDynamicIndexBufferHandle handle) override;

    void SetState(GpuStateFlags state, uint32_t rgba) override;
    void SetTransform(const void* mtx, uint16_t num) override;
    void SetUniform(GpuUniformHandle handle, const void* value, uint16_t num) override;
    void SetTexture(uint8_t stage, GpuUniformHandle sampler, GpuTextureHandle handle, uint32_t flags) override;
    void SetVertexBuffer(uint8_t stream, GpuVertexBufferHandle handle) override;
    void SetIndexBufferStatic(GpuIndexBufferHandle handle) override;
    void SetIndexBufferDynamic(GpuDynamicIndexBufferHandle handle) override;
    void SetBuffer(uint8_t stage, GpuDynamicIndexBufferHandle handle, GpuAccess access) override;

    void Submit(uint16_t id, GpuProgramHandle program, uint32_t depth, bool preserveState) override;
    void Dispatch(uint16_t id, GpuProgramHandle program, uint32_t x, uint32_t y, uint32_t z) override;

    void SetPaletteColor(uint8_t index, float r, float g, float b, float a) override;

    uint16_t CreateVertexLayout(const void* bgfx_layout_ptr) override;

    const char* GetLastFatalError() override;
};

} // namespace kernel_engine::render::bgfx

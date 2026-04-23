#pragma once

#include "gpu_types.hpp"
#include <cstdint>

namespace kernel_engine::render::bgfx
{

/**
 * @brief Professional Hardware Abstraction Layer (HAL) for GPU operations.
 * 100% independent of BGFX headers.
 */
class GpuDeviceInterface
{
public:
    virtual ~GpuDeviceInterface() = default;

    // ── Lifecycle ────────────────────────────────────────────────────────────
    virtual bool Init(const GpuInitConfig& config) = 0;
    virtual void Shutdown() = 0;
    virtual uint32_t Frame(bool capture = false) = 0;

    // ── Memory Management ────────────────────────────────────────────────────
    virtual const GpuMemoryBuffer* Alloc(uint32_t size) = 0;
    virtual const GpuMemoryBuffer* Copy(const void* data, uint32_t size) = 0;
    virtual const GpuMemoryBuffer* MakeRef(const void* data, uint32_t size) = 0;

    // ── View Management ──────────────────────────────────────────────────────
    virtual void SetViewClear(uint16_t id, uint16_t flags, uint32_t rgba, float depth, uint8_t stencil) = 0;
    virtual void SetViewRect(uint16_t id, uint16_t x, uint16_t y, uint16_t width, uint16_t height) = 0;
    virtual void SetViewMode(uint16_t id, GpuViewMode mode) = 0;
    virtual void SetViewTransform(uint16_t id, const void* view, const void* proj) = 0;
    virtual void SetViewFrameBuffer(uint16_t id, GpuFrameBufferHandle handle) = 0;
    virtual void Touch(uint16_t id) = 0;

    // ── Resource Creation ────────────────────────────────────────────────────
    virtual GpuShaderHandle CreateShader(const GpuMemoryBuffer* mem) = 0;
    virtual GpuProgramHandle CreateProgram(GpuShaderHandle vsh, GpuShaderHandle fsh, bool destroyShaders) = 0;
    virtual GpuProgramHandle CreateComputeProgram(GpuShaderHandle csh, bool destroyShaders) = 0;
    
    virtual GpuVertexBufferHandle CreateVertexBuffer(const GpuMemoryBuffer* mem, uint16_t layout_handle) = 0;
    virtual GpuIndexBufferHandle CreateIndexBuffer(const GpuMemoryBuffer* mem) = 0;
    virtual GpuDynamicIndexBufferHandle CreateDynamicIndexBuffer(uint32_t num, uint16_t flags) = 0;
    virtual void UpdateDynamicIndexBuffer(GpuDynamicIndexBufferHandle handle, uint32_t startIndex, const GpuMemoryBuffer* mem) = 0;

    virtual GpuTextureHandle CreateTexture2D(uint16_t width, uint16_t height, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem) = 0;
    virtual GpuTextureHandle CreateTextureCube(uint16_t size, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem) = 0;
    virtual GpuFrameBufferHandle CreateFrameBuffer(uint8_t num, const GpuTextureHandle* handles, bool destroyTextures) = 0;
    virtual GpuTextureHandle GetTexture(GpuFrameBufferHandle handle, uint8_t attachment) = 0;

    virtual GpuUniformHandle CreateUniform(const char* name, GpuUniformType type, uint16_t num) = 0;

    // ── Resource Destruction ─────────────────────────────────────────────────
    virtual void DestroyShader(GpuShaderHandle handle) = 0;
    virtual void DestroyProgram(GpuProgramHandle handle) = 0;
    virtual void DestroyUniform(GpuUniformHandle handle) = 0;
    virtual void DestroyTexture(GpuTextureHandle handle) = 0;
    virtual void DestroyFrameBuffer(GpuFrameBufferHandle handle) = 0;
    virtual void DestroyVertexBuffer(GpuVertexBufferHandle handle) = 0;
    virtual void DestroyIndexBuffer(GpuIndexBufferHandle handle) = 0;
    virtual void DestroyDynamicIndexBuffer(GpuDynamicIndexBufferHandle handle) = 0;

    // ── State & Submission ───────────────────────────────────────────────────
    virtual void SetState(uint64_t state, uint32_t rgba) = 0;
    virtual void SetTransform(const void* mtx, uint16_t num) = 0;
    virtual void SetUniform(GpuUniformHandle handle, const void* value, uint16_t num) = 0;
    virtual void SetTexture(uint8_t stage, GpuUniformHandle sampler, GpuTextureHandle handle, uint32_t flags) = 0;
    virtual void SetVertexBuffer(uint8_t stream, GpuVertexBufferHandle handle) = 0;
    virtual void SetIndexBufferStatic(GpuIndexBufferHandle handle) = 0;
    virtual void SetIndexBufferDynamic(GpuDynamicIndexBufferHandle handle) = 0;
    virtual void SetBuffer(uint8_t stage, GpuDynamicIndexBufferHandle handle, GpuAccess access) = 0;
    
    virtual void Submit(uint16_t id, GpuProgramHandle program, uint32_t depth, bool preserveState) = 0;
    virtual void Dispatch(uint16_t id, GpuProgramHandle program, uint32_t x, uint32_t y, uint32_t z) = 0;
    
    virtual void SetPaletteColor(uint8_t index, float r, float g, float b, float a) = 0;

    // ── Helper ───────────────────────────────────────────────────────────────
    virtual uint16_t CreateVertexLayout(const void* bgfx_layout_ptr) = 0;
};

/**
 * @brief Real BGFX implementation (HAL implementation).
 */
class BgfxGpuDevice : public GpuDeviceInterface
{
public:
    bool Init(const GpuInitConfig& config) override;
    void Shutdown() override;
    uint32_t Frame(bool capture) override;

    const GpuMemoryBuffer* Alloc(uint32_t size) override;
    const GpuMemoryBuffer* Copy(const void* data, uint32_t size) override;
    const GpuMemoryBuffer* MakeRef(const void* data, uint32_t size) override;

    void SetViewClear(uint16_t id, uint16_t flags, uint32_t rgba, float depth, uint8_t stencil) override;
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

    void SetState(uint64_t state, uint32_t rgba) override;
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
};

} // namespace kernel_engine::render::bgfx

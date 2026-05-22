#pragma once

#include "gpu_types.hpp"
#include <cstdint>
#include <stdexcept>

// Forward declarations for kernel types (outside renderer namespace)
struct ke_allocator;
struct ke_logger;
struct ke_window;

namespace kernel_engine::render
{

// Common texture format constants (match bgfx::TextureFormat::Enum values).
static constexpr uint32_t kTexFmtRGBA8   = 67;
static constexpr uint32_t kTexFmtRGBA16F = 16;
static constexpr uint32_t kTexFmtD16     = 88;
static constexpr uint32_t kTexFmtR32F    = 44;

// Texture flags (match BGFX_TEXTURE_* bits).
static constexpr uint64_t kTexFlagRT = UINT64_C(0x0000001000000000);

// Vertex layout type hints passed as layout_handle to CreateVertexBuffer.
static constexpr uint16_t kVertexLayoutStandard     = 0xFFFF; // Position+Normal+TexCoord0+Tangent
static constexpr uint16_t kVertexLayoutPositionOnly = 0xFFFE; // Position only (3 floats)

const char* GetLastFatalError();

// ── BgfxFatalException ───────────────────────────────────────────────────

class BgfxFatalException : public std::runtime_error
{
public:
    BgfxFatalException(const char* msg) : std::runtime_error(msg) {}
};

/**
 * @brief Contract for GPU backend implementations.
 * 100% independent of BGFX headers.
 */
class GpuDevice
{
public:
    virtual ~GpuDevice() = default;

    virtual void SetLogger(struct ke_logger* logger) = 0;

    // ── Lifecycle ────────────────────────────────────────────────────────────
    virtual bool Init(const GpuInitConfig& config) = 0;
    virtual void Shutdown() = 0;
    virtual uint32_t Frame(bool capture = false) = 0;

    /// Returns the shader subdirectory for the active backend (e.g. "spirv", "dx11").
    /// Valid only after Init() succeeds.
    virtual const char* GetShaderSubdir() const = 0;

    /// Returns the clip-space (NDC) convention this backend expects matrices in. Valid after Init().
    virtual GpuNdcConvention GetNdcConvention() const = 0;

    // ── Memory Management ────────────────────────────────────────────────────
    virtual const GpuMemoryBuffer* Alloc(uint32_t size) = 0;
    virtual const GpuMemoryBuffer* Copy(const void* data, uint32_t size) = 0;
    virtual const GpuMemoryBuffer* MakeRef(const void* data, uint32_t size) = 0;

    // ── View Management ──────────────────────────────────────────────────────
    virtual void SetViewClear(uint16_t id, GpuClearFlags flags, uint32_t rgba, float depth, uint8_t stencil) = 0;
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
    virtual void SetState(GpuStateFlags state, uint32_t rgba) = 0;
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

    virtual const char* GetLastFatalError() = 0;
};

} // namespace kernel_engine::render

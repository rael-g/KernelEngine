#pragma once

#include <kernel_engine/render/contract/render_export.h>
#include <cstdint>

// Forward declarations for kernel types (outside renderer namespace)
struct ke_allocator;
struct ke_logger;
struct ke_window;

namespace kernel_engine::render
{

// ── Abstract Handles (Opaque IDs) ───────────────────────────────────────────

using GpuShaderHandle              = uint16_t;
using GpuProgramHandle             = uint16_t;
using GpuUniformHandle             = uint16_t;
using GpuTextureHandle             = uint16_t;
using GpuFrameBufferHandle         = uint16_t;
using GpuVertexBufferHandle        = uint16_t;
using GpuIndexBufferHandle         = uint16_t;
using GpuDynamicIndexBufferHandle  = uint16_t;

static constexpr uint16_t kGpuInvalidHandle = 0xffff;

// ── Memory Management ────────────────────────────────────────────────────────

struct GpuMemoryBuffer
{
    uint8_t* data;
    uint32_t size;
};

// ── Enumerations ─────────────────────────────────────────────────────────────

enum class GpuUniformType : uint8_t
{
    Sampler,
    End,
    Vec4,
    Mat3,
    Mat4
};

enum class GpuViewMode : uint8_t
{
    Default,
    Sequential,
    DepthAscending,
    DepthDescending
};

enum class GpuAccess : uint8_t
{
    Read,
    Write,
    ReadWrite
};

// ── Clip-space (NDC) convention the backend expects matrices in ──────────────

struct GpuNdcConvention
{
    bool z_zero_to_one; // true = clip z in [0,1] (Vulkan/D3D), false = [-1,1] (OpenGL)
    bool y_flip;        // true = projection must flip Y for this backend's framebuffer origin
    bool left_handed;   // true = left-handed clip space
};

// ── Render state / clear flags (backend-agnostic, semantic) ──────────────────
// These are NOT bgfx bit values. The active backend translates them to its own
// encoding (e.g. BGFX_STATE_*/BGFX_CLEAR_*), so render-core stays backend-neutral.

enum class GpuClearFlags : uint16_t
{
    None    = 0,
    Color   = 1u << 0,
    Depth   = 1u << 1,
    Stencil = 1u << 2,
};

enum class GpuStateFlags : uint64_t
{
    None            = 0,
    WriteR          = UINT64_C(1) << 0,
    WriteG          = UINT64_C(1) << 1,
    WriteB          = UINT64_C(1) << 2,
    WriteA          = UINT64_C(1) << 3,
    WriteRgb        = WriteR | WriteG | WriteB,
    WriteRgba       = WriteR | WriteG | WriteB | WriteA,
    WriteZ          = UINT64_C(1) << 4,   // depth write
    DepthTestLess   = UINT64_C(1) << 5,
    DepthTestLEqual = UINT64_C(1) << 6,
    CullCw          = UINT64_C(1) << 7,
    CullCcw         = UINT64_C(1) << 8,
    Msaa            = UINT64_C(1) << 9,
    BlendAlpha      = UINT64_C(1) << 10,
    BlendAdditive   = UINT64_C(1) << 11,
};

constexpr GpuClearFlags operator|(GpuClearFlags a, GpuClearFlags b)
{
    return static_cast<GpuClearFlags>(static_cast<uint16_t>(a) | static_cast<uint16_t>(b));
}
constexpr bool HasFlag(GpuClearFlags v, GpuClearFlags f)
{
    return (static_cast<uint16_t>(v) & static_cast<uint16_t>(f)) != 0;
}

constexpr GpuStateFlags operator|(GpuStateFlags a, GpuStateFlags b)
{
    return static_cast<GpuStateFlags>(static_cast<uint64_t>(a) | static_cast<uint64_t>(b));
}
constexpr bool HasFlag(GpuStateFlags v, GpuStateFlags f)
{
    return (static_cast<uint64_t>(v) & static_cast<uint64_t>(f)) != 0;
}

// ── Configuration Structs ───────────────────────────────────────────────────

struct GpuInitConfig
{
    void*    native_window_handle;
    uint32_t width;
    uint32_t height;
    uint32_t renderer_type;
    bool     debug;
    bool     vsync;
};

/**
 * @brief Neutral parameters for core renderer initialization.
 */
struct GpuRendererParams
{
    ::ke_allocator* allocator;
    ::ke_logger*    logger;
    const char*     shader_path;
    ::ke_window*    window;
    uint32_t        renderer_type;
    bool            vsync;
};

} // namespace kernel_engine::render

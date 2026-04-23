#pragma once

#include <cstdint>

namespace kernel_engine::render::bgfx
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

/**
 * @brief Abstract representation of a memory buffer owned by the GPU library.
 * Mirrors bgfx::Memory structure but stays neutral.
 */
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

// ── Configuration Structs ───────────────────────────────────────────────────

/**
 * @brief Neutral configuration for backend initialization.
 */
struct GpuInitConfig
{
    void*    native_window_handle;
    uint32_t width;
    uint32_t height;
    uint32_t renderer_type; // Maps to bgfx::RendererType
    bool     debug;
};

} // namespace kernel_engine::render::bgfx

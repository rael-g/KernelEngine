#pragma once

#include "render_export.h"
#include <cstdint>

// Forward declarations for kernel types (outside renderer namespace)
struct ke_allocator;
struct ke_logger;
struct ke_window;

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

} // namespace kernel_engine::render::bgfx

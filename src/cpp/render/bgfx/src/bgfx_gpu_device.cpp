#include "gpu_device.hpp"
#include <bgfx/bgfx.h>
#include <bgfx/platform.h>
#include <cstring>
#include <vector>
#include <stdarg.h>

namespace kernel_engine::render::bgfx
{

// ── BgfxLogCallback Implementation ────────────────────────────────────────

class BgfxLogCallback : public ::bgfx::CallbackI
{
public:
    void fatal(const char *_filePath, uint16_t _line, ::bgfx::Fatal::Enum _code, const char *_str) override {}
    void traceVargs(const char *_filePath, uint16_t _line, const char *_format, va_list _argList) override {}
    void profilerBegin(const char *, uint32_t, const char *, uint16_t) override {}
    void profilerBeginLiteral(const char *, uint32_t, const char *, uint16_t) override {}
    void profilerEnd() override {}
    uint32_t cacheReadSize(uint64_t) override { return 0; }
    bool cacheRead(uint64_t, void *, uint32_t) override { return false; }
    void cacheWrite(uint64_t, const void *, uint32_t) override {}
    void screenShot(const char *, uint32_t, uint32_t, uint32_t, const void *, uint32_t, bool) override {}
    void captureBegin(uint32_t, uint32_t, uint32_t, ::bgfx::TextureFormat::Enum, bool) override {}
    void captureEnd() override {}
    void captureFrame(const void *, uint32_t) override {}
};

static BgfxLogCallback s_bgfx_callback;

// ── Internal Helpers (Type Conversion) ───────────────────────────────────────

static ::bgfx::UniformType::Enum ToBgfx(GpuUniformType type)
{
    switch (type) {
        case GpuUniformType::Sampler: return ::bgfx::UniformType::Sampler;
        case GpuUniformType::Vec4:    return ::bgfx::UniformType::Vec4;
        case GpuUniformType::Mat3:    return ::bgfx::UniformType::Mat3;
        case GpuUniformType::Mat4:    return ::bgfx::UniformType::Mat4;
        default: return ::bgfx::UniformType::End;
    }
}

static ::bgfx::ViewMode::Enum ToBgfx(GpuViewMode mode)
{
    switch (mode) {
        case GpuViewMode::Sequential:      return ::bgfx::ViewMode::Sequential;
        case GpuViewMode::DepthAscending:  return ::bgfx::ViewMode::DepthAscending;
        case GpuViewMode::DepthDescending: return ::bgfx::ViewMode::DepthDescending;
        default: return ::bgfx::ViewMode::Default;
    }
}

static ::bgfx::Access::Enum ToBgfx(GpuAccess access)
{
    switch (access) {
        case GpuAccess::Write:     return ::bgfx::Access::Write;
        case GpuAccess::ReadWrite: return ::bgfx::Access::ReadWrite;
        default: return ::bgfx::Access::Read;
    }
}

// ── BgfxGpuDevice Implementation ─────────────────────────────────────────────

bool BgfxGpuDevice::Init(const GpuInitConfig& config)
{
    ::bgfx::Init init;
    init.type = (::bgfx::RendererType::Enum)config.renderer_type;
    init.platformData.nwh = config.native_window_handle;
    init.resolution.width  = config.width;
    init.resolution.height = config.height;
    init.resolution.reset  = BGFX_RESET_VSYNC;
    init.debug = config.debug;
    init.callback = &s_bgfx_callback;
    return ::bgfx::init(init);
}

void BgfxGpuDevice::Shutdown() { ::bgfx::shutdown(); }
uint32_t BgfxGpuDevice::Frame(bool capture) { return ::bgfx::frame(capture); }

const GpuMemoryBuffer* BgfxGpuDevice::Alloc(uint32_t size) { return (const GpuMemoryBuffer*)::bgfx::alloc(size); }
const GpuMemoryBuffer* BgfxGpuDevice::Copy(const void* data, uint32_t size) { return (const GpuMemoryBuffer*)::bgfx::copy(data, size); }
const GpuMemoryBuffer* BgfxGpuDevice::MakeRef(const void* data, uint32_t size) { return (const GpuMemoryBuffer*)::bgfx::makeRef(data, size); }

void BgfxGpuDevice::SetViewClear(uint16_t id, uint16_t flags, uint32_t rgba, float depth, uint8_t stencil) { ::bgfx::setViewClear(id, flags, rgba, depth, stencil); }
void BgfxGpuDevice::SetViewRect(uint16_t id, uint16_t x, uint16_t y, uint16_t width, uint16_t height) { ::bgfx::setViewRect(id, x, y, width, height); }
void BgfxGpuDevice::SetViewMode(uint16_t id, GpuViewMode mode) { ::bgfx::setViewMode(id, ToBgfx(mode)); }
void BgfxGpuDevice::SetViewTransform(uint16_t id, const void* view, const void* proj) { ::bgfx::setViewTransform(id, view, proj); }
void BgfxGpuDevice::SetViewFrameBuffer(uint16_t id, GpuFrameBufferHandle handle) { ::bgfx::setViewFrameBuffer(id, ::bgfx::FrameBufferHandle{handle}); }
void BgfxGpuDevice::Touch(uint16_t id) { ::bgfx::touch(id); }

GpuShaderHandle BgfxGpuDevice::CreateShader(const GpuMemoryBuffer* mem) { return ::bgfx::createShader((const ::bgfx::Memory*)mem).idx; }
GpuProgramHandle BgfxGpuDevice::CreateProgram(GpuShaderHandle vsh, GpuShaderHandle fsh, bool destroyShaders) { return ::bgfx::createProgram(::bgfx::ShaderHandle{vsh}, ::bgfx::ShaderHandle{fsh}, destroyShaders).idx; }
GpuProgramHandle BgfxGpuDevice::CreateComputeProgram(GpuShaderHandle csh, bool destroyShaders) { return ::bgfx::createProgram(::bgfx::ShaderHandle{csh}, destroyShaders).idx; }

GpuVertexBufferHandle BgfxGpuDevice::CreateVertexBuffer(const GpuMemoryBuffer* mem, uint16_t layout_handle)
{
    // Simplified vertex layout handling: use a standard layout if handle is 0
    ::bgfx::VertexLayout layout;
    layout.begin()
        .add(::bgfx::Attrib::Position,  3, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::Normal,    3, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::TexCoord0, 2, ::bgfx::AttribType::Float)
        .add(::bgfx::Attrib::Tangent,   4, ::bgfx::AttribType::Float)
        .end();

    return ::bgfx::createVertexBuffer((const ::bgfx::Memory*)mem, layout).idx;
}

GpuIndexBufferHandle BgfxGpuDevice::CreateIndexBuffer(const GpuMemoryBuffer* mem) { return ::bgfx::createIndexBuffer((const ::bgfx::Memory*)mem).idx; }
GpuDynamicIndexBufferHandle BgfxGpuDevice::CreateDynamicIndexBuffer(uint32_t num, uint16_t flags) { return ::bgfx::createDynamicIndexBuffer(num, flags).idx; }
void BgfxGpuDevice::UpdateDynamicIndexBuffer(GpuDynamicIndexBufferHandle handle, uint32_t startIndex, const GpuMemoryBuffer* mem) { ::bgfx::update(::bgfx::DynamicIndexBufferHandle{handle}, startIndex, (const ::bgfx::Memory*)mem); }

GpuTextureHandle BgfxGpuDevice::CreateTexture2D(uint16_t width, uint16_t height, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem)
{
    return ::bgfx::createTexture2D(width, height, hasMips, numLayers, (::bgfx::TextureFormat::Enum)format, flags, (const ::bgfx::Memory*)mem).idx;
}

GpuTextureHandle BgfxGpuDevice::CreateTextureCube(uint16_t size, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem)
{
    return ::bgfx::createTextureCube(size, hasMips, numLayers, (::bgfx::TextureFormat::Enum)format, flags, (const ::bgfx::Memory*)mem).idx;
}

GpuFrameBufferHandle BgfxGpuDevice::CreateFrameBuffer(uint8_t num, const GpuTextureHandle* handles, bool destroyTextures)
{
    std::vector<::bgfx::TextureHandle> bgfx_handles(num);
    for(uint8_t i=0; i<num; ++i) bgfx_handles[i] = {handles[i]};
    return ::bgfx::createFrameBuffer(num, bgfx_handles.data(), destroyTextures).idx;
}

GpuTextureHandle BgfxGpuDevice::GetTexture(GpuFrameBufferHandle handle, uint8_t attachment) { return ::bgfx::getTexture(::bgfx::FrameBufferHandle{handle}, attachment).idx; }

GpuUniformHandle BgfxGpuDevice::CreateUniform(const char* name, GpuUniformType type, uint16_t num) { return ::bgfx::createUniform(name, ToBgfx(type), num).idx; }

void BgfxGpuDevice::DestroyShader(GpuShaderHandle handle) { ::bgfx::destroy(::bgfx::ShaderHandle{handle}); }
void BgfxGpuDevice::DestroyProgram(GpuProgramHandle handle) { ::bgfx::destroy(::bgfx::ProgramHandle{handle}); }
void BgfxGpuDevice::DestroyUniform(GpuUniformHandle handle) { ::bgfx::destroy(::bgfx::UniformHandle{handle}); }
void BgfxGpuDevice::DestroyTexture(GpuTextureHandle handle) { ::bgfx::destroy(::bgfx::TextureHandle{handle}); }
void BgfxGpuDevice::DestroyFrameBuffer(GpuFrameBufferHandle handle) { ::bgfx::destroy(::bgfx::FrameBufferHandle{handle}); }
void BgfxGpuDevice::DestroyVertexBuffer(GpuVertexBufferHandle handle) { ::bgfx::destroy(::bgfx::VertexBufferHandle{handle}); }
void BgfxGpuDevice::DestroyIndexBuffer(GpuIndexBufferHandle handle) { ::bgfx::destroy(::bgfx::IndexBufferHandle{handle}); }
void BgfxGpuDevice::DestroyDynamicIndexBuffer(GpuDynamicIndexBufferHandle handle) { ::bgfx::destroy(::bgfx::DynamicIndexBufferHandle{handle}); }

void BgfxGpuDevice::SetState(uint64_t state, uint32_t rgba) { ::bgfx::setState(state, rgba); }
void BgfxGpuDevice::SetTransform(const void* mtx, uint16_t num) { ::bgfx::setTransform(mtx, num); }
void BgfxGpuDevice::SetUniform(GpuUniformHandle handle, const void* value, uint16_t num) { ::bgfx::setUniform(::bgfx::UniformHandle{handle}, value, num); }
void BgfxGpuDevice::SetTexture(uint8_t stage, GpuUniformHandle sampler, GpuTextureHandle handle, uint32_t flags) { ::bgfx::setTexture(stage, ::bgfx::UniformHandle{sampler}, ::bgfx::TextureHandle{handle}, flags); }
void BgfxGpuDevice::SetVertexBuffer(uint8_t stream, GpuVertexBufferHandle handle) { ::bgfx::setVertexBuffer(stream, ::bgfx::VertexBufferHandle{handle}); }
void BgfxGpuDevice::SetIndexBufferStatic(GpuIndexBufferHandle handle) { ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{handle}); }
void BgfxGpuDevice::SetIndexBufferDynamic(GpuDynamicIndexBufferHandle handle) { ::bgfx::setIndexBuffer(::bgfx::DynamicIndexBufferHandle{handle}); }
void BgfxGpuDevice::SetBuffer(uint8_t stage, GpuDynamicIndexBufferHandle handle, GpuAccess access) { ::bgfx::setBuffer(stage, ::bgfx::DynamicIndexBufferHandle{handle}, ToBgfx(access)); }

void BgfxGpuDevice::Submit(uint16_t id, GpuProgramHandle program, uint32_t depth, bool preserveState) { ::bgfx::submit(id, ::bgfx::ProgramHandle{program}, depth, preserveState); }
void BgfxGpuDevice::Dispatch(uint16_t id, GpuProgramHandle program, uint32_t x, uint32_t y, uint32_t z) { ::bgfx::dispatch(id, ::bgfx::ProgramHandle{program}, x, y, z); }

void BgfxGpuDevice::SetPaletteColor(uint8_t index, float r, float g, float b, float a) { ::bgfx::setPaletteColor(index, r, g, b, a); }

uint16_t BgfxGpuDevice::CreateVertexLayout(const void* bgfx_layout_ptr)
{
    return ::bgfx::createVertexLayout(*(const ::bgfx::VertexLayout*)bgfx_layout_ptr).idx;
}

} // namespace kernel_engine::render::bgfx

#include "bgfx_gpu_device.hpp"
#include <kernel_engine/kernel/common/thread_name.h>
#include <bgfx/bgfx.h>
#include <bgfx/platform.h>
#include <cstring>
#include <vector>
#include <stdarg.h>
#include <cstdio>
#ifdef _WIN32
#include <windows.h>
#endif

#include <kernel_engine/kernel/logger/logger.h>
#include <stdexcept>

namespace kernel_engine::render
{

// ── Semantic flag translation (the ONLY place bgfx encoding lives) ─────────

namespace
{
uint16_t ToBgfxClear(GpuClearFlags flags)
{
    uint16_t out = BGFX_CLEAR_NONE;
    if (HasFlag(flags, GpuClearFlags::Color))   out |= BGFX_CLEAR_COLOR;
    if (HasFlag(flags, GpuClearFlags::Depth))   out |= BGFX_CLEAR_DEPTH;
    if (HasFlag(flags, GpuClearFlags::Stencil)) out |= BGFX_CLEAR_STENCIL;
    return out;
}

uint64_t ToBgfxState(GpuStateFlags state)
{
    uint64_t out = 0;
    if (HasFlag(state, GpuStateFlags::WriteR))          out |= BGFX_STATE_WRITE_R;
    if (HasFlag(state, GpuStateFlags::WriteG))          out |= BGFX_STATE_WRITE_G;
    if (HasFlag(state, GpuStateFlags::WriteB))          out |= BGFX_STATE_WRITE_B;
    if (HasFlag(state, GpuStateFlags::WriteA))          out |= BGFX_STATE_WRITE_A;
    if (HasFlag(state, GpuStateFlags::WriteZ))          out |= BGFX_STATE_WRITE_Z;
    if (HasFlag(state, GpuStateFlags::DepthTestLess))   out |= BGFX_STATE_DEPTH_TEST_LESS;
    if (HasFlag(state, GpuStateFlags::DepthTestLEqual)) out |= BGFX_STATE_DEPTH_TEST_LEQUAL;
    if (HasFlag(state, GpuStateFlags::CullCw))          out |= BGFX_STATE_CULL_CW;
    if (HasFlag(state, GpuStateFlags::CullCcw))         out |= BGFX_STATE_CULL_CCW;
    if (HasFlag(state, GpuStateFlags::Msaa))            out |= BGFX_STATE_MSAA;
    if (HasFlag(state, GpuStateFlags::BlendAlpha))      out |= BGFX_STATE_BLEND_ALPHA;
    if (HasFlag(state, GpuStateFlags::BlendAdditive))   out |= BGFX_STATE_BLEND_ADD;
    return out;
}
} // namespace

// ── Fatal Error Handling ─────────────────────────────────────────────────

static char s_last_fatal_error[1024] = {0};

void SetLastFatalError(const char* msg) {
    if (msg) {
        std::strncpy(s_last_fatal_error, msg, sizeof(s_last_fatal_error) - 1);
    }
}

const char* GetLastFatalError() {
    return s_last_fatal_error;
}

} // namespace kernel_engine::render

namespace kernel_engine::render::bgfx
{

// ── BgfxLogCallback Implementation ────────────────────────────────────────

class BgfxLogCallback : public ::bgfx::CallbackI
{
public:
    void SetLogger(struct ke_logger* logger) { logger_ = logger; }

    void fatal(const char *_filePath, uint16_t _line, ::bgfx::Fatal::Enum _code, const char *_str) override
    {
        char buf[1024];
        snprintf(buf, sizeof(buf), "[bgfx FATAL] %s:%u code=%d: %s", _filePath, _line, (int)_code, _str);
        
        SetLastFatalError(buf);

        if (logger_) {
            ke_log_event ev = { KE_LOG_LEVEL_CRITICAL, "bgfx", buf };
            logger_->log(logger_, &ev);
        }
        fprintf(stderr, "%s\n", buf);
        fflush(stderr);
        
        throw BgfxFatalException(buf);
    }

    void traceVargs(const char *_filePath, uint16_t _line, const char *_format, va_list _argList) override
    {
        if (logger_) {
            char buf[1024];
            vsnprintf(buf, sizeof(buf), _format, _argList);
            // Trace from bgfx is usually verbose, map to DEBUG per backlog Y.1
            ke_log_event ev = { KE_LOG_LEVEL_DEBUG, "bgfx", buf };
            logger_->log(logger_, &ev);
        } else {
            fprintf(stderr, "[bgfx] %s:%u ", _filePath, _line);
            vfprintf(stderr, _format, _argList);
            fflush(stderr);
        }
    }
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

private:
    struct ke_logger* logger_ = nullptr;
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

void BgfxGpuDevice::SetLogger(struct ke_logger* logger)
{
    s_bgfx_callback.SetLogger(logger);
}

bool BgfxGpuDevice::Init(const GpuInitConfig& config)
{
    ke_thread_assert_current("ke.render");
    
    // Inject logger for bgfx callbacks
    // Note: We need access to the logger here. Currently GpuInitConfig doesn't have it.
    // However, BgfxGpuDevice is usually owned by CoreRenderer which has it.
    // For now, let's assume we can get it if we modify GpuInitConfig or if we set it separately.
    // Actually, I'll add SetLogger to GpuDevice interface.

    ::bgfx::Init init;
    init.type = (::bgfx::RendererType::Enum)config.renderer_type;
    init.platformData.nwh = config.native_window_handle;
    init.resolution.width  = config.width;
    init.resolution.height = config.height;
    // In Remote Desktop sessions, vsync with Vulkan causes the driver to briefly
    // request exclusive display access, momentarily changing the screen resolution.
    uint32_t reset_flags = config.vsync ? BGFX_RESET_VSYNC : BGFX_RESET_NONE;
#ifdef _WIN32
    bool is_remote = GetSystemMetrics(SM_REMOTESESSION) != 0;
    fprintf(stderr, "[ke] SM_REMOTESESSION = %d\n", (int)is_remote);
    fflush(stderr);
    if (is_remote) {
        reset_flags = BGFX_RESET_NONE;
        // Force D3D11 in Remote Desktop: Vulkan enumerates VK_KHR_display
        // which causes the display to momentarily change resolution in RDP.
        init.type = ::bgfx::RendererType::Direct3D11;
        fprintf(stderr, "[ke] RDP detected: switching to D3D11\n");
        fflush(stderr);
    }
#endif
    init.resolution.reset  = reset_flags;
    init.debug = config.debug;
    init.callback = &s_bgfx_callback;
    return ::bgfx::init(init);
}

void BgfxGpuDevice::Shutdown()
{
    ke_thread_assert_current("ke.render");
    ::bgfx::shutdown();
}

uint32_t BgfxGpuDevice::Frame(bool capture)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::frame(capture);
}

const char* BgfxGpuDevice::GetShaderSubdir() const
{
    ke_thread_assert_current("ke.render");
    switch (::bgfx::getRendererType()) {
        case ::bgfx::RendererType::Direct3D11: return "dx11";
        case ::bgfx::RendererType::Direct3D12: return "dx12";
        case ::bgfx::RendererType::OpenGL:     return "glsl";
        case ::bgfx::RendererType::OpenGLES:   return "essl";
        case ::bgfx::RendererType::Metal:      return "metal";
        case ::bgfx::RendererType::Vulkan:     return "spirv";
        default:                               return "spirv";
    }
}

GpuNdcConvention BgfxGpuDevice::GetNdcConvention() const
{
    ke_thread_assert_current("ke.render");
    const ::bgfx::Caps* caps = ::bgfx::getCaps();
    GpuNdcConvention conv{};
    // homogeneousDepth = true → clip z in [-1,1] (OpenGL); false → [0,1] (Vulkan/D3D).
    conv.z_zero_to_one = caps ? !caps->homogeneousDepth : true;
    // Our projection builders are right-handed and don't flip Y (bgfx abstracts framebuffer
    // origin per backend), matching the current hand-tuned matrices.
    conv.y_flip      = false;
    conv.left_handed = false;
    return conv;
}


const GpuMemoryBuffer* BgfxGpuDevice::Alloc(uint32_t size)
{
    ke_thread_assert_current("ke.render");
    return (const GpuMemoryBuffer*)::bgfx::alloc(size);
}

const GpuMemoryBuffer* BgfxGpuDevice::Copy(const void* data, uint32_t size)
{
    ke_thread_assert_current("ke.render");
    return (const GpuMemoryBuffer*)::bgfx::copy(data, size);
}

const GpuMemoryBuffer* BgfxGpuDevice::MakeRef(const void* data, uint32_t size)
{
    ke_thread_assert_current("ke.render");
    return (const GpuMemoryBuffer*)::bgfx::makeRef(data, size);
}

void BgfxGpuDevice::SetViewClear(uint16_t id, GpuClearFlags flags, uint32_t rgba, float depth, uint8_t stencil)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setViewClear(id, ToBgfxClear(flags), rgba, depth, stencil);
}

void BgfxGpuDevice::SetViewRect(uint16_t id, uint16_t x, uint16_t y, uint16_t width, uint16_t height)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setViewRect(id, x, y, width, height);
}

void BgfxGpuDevice::SetViewMode(uint16_t id, GpuViewMode mode)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setViewMode(id, ToBgfx(mode));
}

void BgfxGpuDevice::SetViewTransform(uint16_t id, const void* view, const void* proj)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setViewTransform(id, view, proj);
}

void BgfxGpuDevice::SetViewFrameBuffer(uint16_t id, GpuFrameBufferHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setViewFrameBuffer(id, ::bgfx::FrameBufferHandle{handle});
}

void BgfxGpuDevice::Touch(uint16_t id)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::touch(id);
}

GpuShaderHandle BgfxGpuDevice::CreateShader(const GpuMemoryBuffer* mem)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::createShader((const ::bgfx::Memory*)mem).idx;
}

GpuProgramHandle BgfxGpuDevice::CreateProgram(GpuShaderHandle vsh, GpuShaderHandle fsh, bool destroyShaders)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::createProgram(::bgfx::ShaderHandle{vsh}, ::bgfx::ShaderHandle{fsh}, destroyShaders).idx;
}

GpuProgramHandle BgfxGpuDevice::CreateComputeProgram(GpuShaderHandle csh, bool destroyShaders)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::createProgram(::bgfx::ShaderHandle{csh}, destroyShaders).idx;
}

GpuVertexBufferHandle BgfxGpuDevice::CreateVertexBuffer(const GpuMemoryBuffer* mem, uint16_t layout_handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::VertexLayout layout;
    if (layout_handle == kVertexLayoutPositionOnly) {
        layout.begin()
            .add(::bgfx::Attrib::Position, 3, ::bgfx::AttribType::Float)
            .end();
    } else {
        layout.begin()
            .add(::bgfx::Attrib::Position,  3, ::bgfx::AttribType::Float)
            .add(::bgfx::Attrib::Normal,    3, ::bgfx::AttribType::Float)
            .add(::bgfx::Attrib::TexCoord0, 2, ::bgfx::AttribType::Float)
            .add(::bgfx::Attrib::Tangent,   4, ::bgfx::AttribType::Float)
            .end();
    }
    return ::bgfx::createVertexBuffer((const ::bgfx::Memory*)mem, layout).idx;
}

GpuIndexBufferHandle BgfxGpuDevice::CreateIndexBuffer(const GpuMemoryBuffer* mem)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::createIndexBuffer((const ::bgfx::Memory*)mem).idx;
}

GpuDynamicIndexBufferHandle BgfxGpuDevice::CreateDynamicIndexBuffer(uint32_t num, uint16_t flags)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::createDynamicIndexBuffer(num, flags).idx;
}

void BgfxGpuDevice::UpdateDynamicIndexBuffer(GpuDynamicIndexBufferHandle handle, uint32_t startIndex, const GpuMemoryBuffer* mem)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::update(::bgfx::DynamicIndexBufferHandle{handle}, startIndex, (const ::bgfx::Memory*)mem);
}

GpuTextureHandle BgfxGpuDevice::CreateTexture2D(uint16_t width, uint16_t height, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::createTexture2D(width, height, hasMips, numLayers, (::bgfx::TextureFormat::Enum)format, flags, (const ::bgfx::Memory*)mem).idx;
}

GpuTextureHandle BgfxGpuDevice::CreateTextureCube(uint16_t size, bool hasMips, uint16_t numLayers, uint32_t format, uint64_t flags, const GpuMemoryBuffer* mem)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::createTextureCube(size, hasMips, numLayers, (::bgfx::TextureFormat::Enum)format, flags, (const ::bgfx::Memory*)mem).idx;
}

GpuFrameBufferHandle BgfxGpuDevice::CreateFrameBuffer(uint8_t num, const GpuTextureHandle* handles, bool destroyTextures)
{
    ke_thread_assert_current("ke.render");
    std::vector<::bgfx::TextureHandle> bgfx_handles(num);
    for(uint8_t i=0; i<num; ++i) bgfx_handles[i] = {handles[i]};
    return ::bgfx::createFrameBuffer(num, bgfx_handles.data(), destroyTextures).idx;
}

GpuTextureHandle BgfxGpuDevice::GetTexture(GpuFrameBufferHandle handle, uint8_t attachment)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::getTexture(::bgfx::FrameBufferHandle{handle}, attachment).idx;
}

GpuUniformHandle BgfxGpuDevice::CreateUniform(const char* name, GpuUniformType type, uint16_t num)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::createUniform(name, ToBgfx(type), num).idx;
}

void BgfxGpuDevice::DestroyShader(GpuShaderHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::destroy(::bgfx::ShaderHandle{handle});
}

void BgfxGpuDevice::DestroyProgram(GpuProgramHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::destroy(::bgfx::ProgramHandle{handle});
}

void BgfxGpuDevice::DestroyUniform(GpuUniformHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::destroy(::bgfx::UniformHandle{handle});
}

void BgfxGpuDevice::DestroyTexture(GpuTextureHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::destroy(::bgfx::TextureHandle{handle});
}

void BgfxGpuDevice::DestroyFrameBuffer(GpuFrameBufferHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::destroy(::bgfx::FrameBufferHandle{handle});
}

void BgfxGpuDevice::DestroyVertexBuffer(GpuVertexBufferHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::destroy(::bgfx::VertexBufferHandle{handle});
}

void BgfxGpuDevice::DestroyIndexBuffer(GpuIndexBufferHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::destroy(::bgfx::IndexBufferHandle{handle});
}

void BgfxGpuDevice::DestroyDynamicIndexBuffer(GpuDynamicIndexBufferHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::destroy(::bgfx::DynamicIndexBufferHandle{handle});
}

void BgfxGpuDevice::SetState(GpuStateFlags state, uint32_t rgba)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setState(ToBgfxState(state), rgba);
}

void BgfxGpuDevice::SetTransform(const void* mtx, uint16_t num)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setTransform(mtx, num);
}

void BgfxGpuDevice::SetUniform(GpuUniformHandle handle, const void* value, uint16_t num)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setUniform(::bgfx::UniformHandle{handle}, value, num);
}

void BgfxGpuDevice::SetTexture(uint8_t stage, GpuUniformHandle sampler, GpuTextureHandle handle, uint32_t flags)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setTexture(stage, ::bgfx::UniformHandle{sampler}, ::bgfx::TextureHandle{handle}, flags);
}

void BgfxGpuDevice::SetVertexBuffer(uint8_t stream, GpuVertexBufferHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setVertexBuffer(stream, ::bgfx::VertexBufferHandle{handle});
}

void BgfxGpuDevice::SetIndexBufferStatic(GpuIndexBufferHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setIndexBuffer(::bgfx::IndexBufferHandle{handle});
}

void BgfxGpuDevice::SetIndexBufferDynamic(GpuDynamicIndexBufferHandle handle)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setIndexBuffer(::bgfx::DynamicIndexBufferHandle{handle});
}

void BgfxGpuDevice::SetBuffer(uint8_t stage, GpuDynamicIndexBufferHandle handle, GpuAccess access)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setBuffer(stage, ::bgfx::DynamicIndexBufferHandle{handle}, ToBgfx(access));
}

void BgfxGpuDevice::Submit(uint16_t id, GpuProgramHandle program, uint32_t depth, bool preserveState)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::submit(id, ::bgfx::ProgramHandle{program}, depth, preserveState);
}

void BgfxGpuDevice::Dispatch(uint16_t id, GpuProgramHandle program, uint32_t x, uint32_t y, uint32_t z)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::dispatch(id, ::bgfx::ProgramHandle{program}, x, y, z);
}

void BgfxGpuDevice::SetPaletteColor(uint8_t index, float r, float g, float b, float a)
{
    ke_thread_assert_current("ke.render");
    ::bgfx::setPaletteColor(index, r, g, b, a);
}

void BgfxGpuDevice::SubmitUiQuad(uint16_t view_id, GpuProgramHandle program,
                                 GpuUniformHandle sampler_uniform, GpuTextureHandle texture,
                                 const UiQuad& q)
{
    ke_thread_assert_current("ke.render");

    // Vertex layout: position (3f, pixels with z=0) + texcoord (2f) + color (4 bytes, premultiplied).
    // 3 floats for position because varying.def.sc declares `a_position : vec3` across all shaders;
    // sharing the attribute slot dodges shader-binding mismatches at the cost of 8 bytes/vertex.
    // 6 vertices = 2 triangles (no index buffer; tiny enough that duplicating the shared edge
    // costs less than the per-quad bookkeeping for an index buffer).
    struct UiVertex { float x, y, z; float u, v; uint32_t abgr; };

    static ::bgfx::VertexLayout layout = []{
        ::bgfx::VertexLayout l;
        l.begin()
            .add(::bgfx::Attrib::Position,  3, ::bgfx::AttribType::Float)
            .add(::bgfx::Attrib::TexCoord0, 2, ::bgfx::AttribType::Float)
            .add(::bgfx::Attrib::Color0,    4, ::bgfx::AttribType::Uint8, /*normalized=*/true)
            .end();
        return l;
    }();

    if (::bgfx::getAvailTransientVertexBuffer(4, layout) < 4) return;
    if (::bgfx::getAvailTransientIndexBuffer(6) < 6) return;

    ::bgfx::TransientVertexBuffer tvb;
    ::bgfx::allocTransientVertexBuffer(&tvb, 4, layout);
    ::bgfx::TransientIndexBuffer  tib;
    ::bgfx::allocTransientIndexBuffer(&tib, 6);
    auto* v = reinterpret_cast<UiVertex*>(tvb.data);
    auto* idx = reinterpret_cast<uint16_t*>(tib.data);

    // Pack RGBA into bgfx's ABGR (little-endian uint32, normalized to bytes).
    auto pack = [](float r, float g, float b, float a) -> uint32_t {
        auto c = [](float f) -> uint32_t {
            int i = (int)(f * 255.0f + 0.5f);
            if (i < 0) i = 0; if (i > 255) i = 255;
            return (uint32_t)i;
        };
        return (c(a) << 24) | (c(b) << 16) | (c(g) << 8) | c(r);
    };
    const uint32_t abgr = pack(q.r, q.g, q.b, q.a);

    // 4 unique corners + 6 indices forming the two triangles. Same exact structure as the
    // engine's built-in mesh quad (geometry_manager creates a quad with this layout) — using
    // it here too dodges the asymmetric-rendering bug we hit with non-indexed 6-vertex draws.
    const float x0 = q.dst_x,             y0 = q.dst_y;
    const float x1 = q.dst_x + q.dst_w,   y1 = q.dst_y + q.dst_h;
    v[0] = {x0, y0, 0.f, q.u0, q.v0, abgr}; // 0: TL
    v[1] = {x1, y0, 0.f, q.u1, q.v0, abgr}; // 1: TR
    v[2] = {x1, y1, 0.f, q.u1, q.v1, abgr}; // 2: BR
    v[3] = {x0, y1, 0.f, q.u0, q.v1, abgr}; // 3: BL

    // Triangle 1: TL → BL → BR ;  Triangle 2: TL → BR → TR (same winding pattern).
    idx[0] = 0; idx[1] = 3; idx[2] = 2;
    idx[3] = 0; idx[4] = 2; idx[5] = 1;

    ::bgfx::setVertexBuffer(0, &tvb, 0, 4);
    ::bgfx::setIndexBuffer(&tib, 0, 6);

    // Bind texture (or skip for solid-color quads — shader uses tint either way).
    if (texture != UINT16_MAX)
        ::bgfx::setTexture(0, ::bgfx::UniformHandle{sampler_uniform}, ::bgfx::TextureHandle{texture});

    // State: write RGB+A, depth-test always-pass (defensive — the UI view shares the backbuffer
    // depth and stale values from the scene pass were occluding half the quad in practice),
    // premultiplied alpha blend, no culling (both triangles wind the same way in screen space
    // but the active backend's NDC flip changes their effective orientation; not setting any
    // cull bit lets both render regardless).
    const uint64_t state =
        BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A |
        BGFX_STATE_DEPTH_TEST_ALWAYS |
        BGFX_STATE_BLEND_FUNC(BGFX_STATE_BLEND_ONE, BGFX_STATE_BLEND_INV_SRC_ALPHA);
    ::bgfx::setState(state);

    ::bgfx::submit(view_id, ::bgfx::ProgramHandle{program});
}

uint16_t BgfxGpuDevice::CreateVertexLayout(const void* bgfx_layout_ptr)
{
    ke_thread_assert_current("ke.render");
    return ::bgfx::createVertexLayout(*(const ::bgfx::VertexLayout*)bgfx_layout_ptr).idx;
}

const char* BgfxGpuDevice::GetLastFatalError()
{
    return kernel_engine::render::GetLastFatalError();
}

} // namespace kernel_engine::render::bgfx

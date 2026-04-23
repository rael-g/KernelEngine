#pragma once

#include <bgfx/bgfx.h>
#include <cstdint>

namespace kernel_engine::render::bgfx
{

/**
 * @brief Professional abstraction for the GPU hardware/library.
 */
class GpuDeviceInterface
{
public:
    virtual ~GpuDeviceInterface() = default;

    // ── Lifecycle ────────────────────────────────────────────────────────────
    virtual bool Init(const ::bgfx::Init& init) = 0;
    virtual void Shutdown() = 0;
    virtual uint32_t Frame(bool capture = false) = 0;

    // ── Memory Management ────────────────────────────────────────────────────
    virtual const ::bgfx::Memory* Alloc(uint32_t size) = 0;
    virtual const ::bgfx::Memory* Copy(const void* data, uint32_t size) = 0;
    virtual const ::bgfx::Memory* MakeRef(const void* data, uint32_t size) = 0;

    // ── View Management ──────────────────────────────────────────────────────
    virtual void SetViewClear(uint16_t id, uint16_t flags, uint32_t rgba, float depth, uint8_t stencil) = 0;
    virtual void SetViewRect(uint16_t id, uint16_t x, uint16_t y, uint16_t width, uint16_t height) = 0;
    virtual void SetViewMode(uint16_t id, ::bgfx::ViewMode::Enum mode) = 0;
    virtual void SetViewTransform(uint16_t id, const void* view, const void* proj) = 0;
    virtual void SetViewFrameBuffer(uint16_t id, ::bgfx::FrameBufferHandle handle) = 0;
    virtual void Touch(uint16_t id) = 0;

    // ── Resource Creation ────────────────────────────────────────────────────
    virtual ::bgfx::ShaderHandle CreateShader(const ::bgfx::Memory* mem) = 0;
    virtual ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, ::bgfx::ShaderHandle fsh, bool destroyShaders) = 0;
    virtual ::bgfx::ProgramHandle CreateComputeProgram(::bgfx::ShaderHandle csh, bool destroyShaders) = 0;
    
    virtual ::bgfx::VertexBufferHandle CreateVertexBuffer(const ::bgfx::Memory* mem, const ::bgfx::VertexLayout& layout) = 0;
    virtual ::bgfx::IndexBufferHandle CreateIndexBuffer(const ::bgfx::Memory* mem) = 0;
    virtual ::bgfx::DynamicIndexBufferHandle CreateDynamicIndexBuffer(uint32_t num, uint16_t flags) = 0;
    virtual void UpdateDynamicIndexBuffer(::bgfx::DynamicIndexBufferHandle handle, uint32_t startIndex, const ::bgfx::Memory* mem) = 0;

    virtual ::bgfx::TextureHandle CreateTexture2D(uint16_t width, uint16_t height, bool hasMips, uint16_t numLayers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) = 0;
    virtual ::bgfx::TextureHandle CreateTextureCube(uint16_t size, bool hasMips, uint16_t numLayers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) = 0;
    virtual ::bgfx::FrameBufferHandle CreateFrameBuffer(uint8_t num, const ::bgfx::TextureHandle* handles, bool destroyTextures) = 0;
    virtual ::bgfx::TextureHandle GetTexture(::bgfx::FrameBufferHandle handle, uint8_t attachment) = 0;

    virtual ::bgfx::UniformHandle CreateUniform(const char* name, ::bgfx::UniformType::Enum type, uint16_t num) = 0;

    // ── Resource Destruction ─────────────────────────────────────────────────
    virtual void Destroy(::bgfx::ShaderHandle handle) = 0;
    virtual void Destroy(::bgfx::ProgramHandle handle) = 0;
    virtual void Destroy(::bgfx::UniformHandle handle) = 0;
    virtual void Destroy(::bgfx::TextureHandle handle) = 0;
    virtual void Destroy(::bgfx::FrameBufferHandle handle) = 0;
    virtual void Destroy(::bgfx::VertexBufferHandle handle) = 0;
    virtual void Destroy(::bgfx::IndexBufferHandle handle) = 0;
    virtual void Destroy(::bgfx::DynamicIndexBufferHandle handle) = 0;

    // ── State & Submission ───────────────────────────────────────────────────
    virtual void SetState(uint64_t state, uint32_t rgba) = 0;
    virtual void SetTransform(const void* mtx, uint16_t num) = 0;
    virtual void SetUniform(::bgfx::UniformHandle handle, const void* value, uint16_t num) = 0;
    virtual void SetTexture(uint8_t stage, ::bgfx::UniformHandle sampler, ::bgfx::TextureHandle handle, uint32_t flags) = 0;
    virtual void SetVertexBuffer(uint8_t stream, ::bgfx::VertexBufferHandle handle) = 0;
    virtual void SetIndexBuffer(::bgfx::IndexBufferHandle handle) = 0;
    virtual void SetIndexBuffer(::bgfx::DynamicIndexBufferHandle handle) = 0;
    virtual void SetBuffer(uint8_t stage, ::bgfx::DynamicIndexBufferHandle handle, ::bgfx::Access::Enum access) = 0;
    
    virtual void Submit(uint16_t id, ::bgfx::ProgramHandle program, uint32_t depth, bool preserveState) = 0;
    virtual void Dispatch(uint16_t id, ::bgfx::ProgramHandle program, uint32_t x, uint32_t y, uint32_t z) = 0;
    
    virtual void SetPaletteColor(uint8_t index, float r, float g, float b, float a) = 0;
};

/**
 * @brief Real BGFX implementation for production use.
 */
class GpuDevice : public GpuDeviceInterface
{
public:
    bool Init(const ::bgfx::Init& init) override { return ::bgfx::init(init); }
    void Shutdown() override { ::bgfx::shutdown(); }
    uint32_t Frame(bool capture) override { return ::bgfx::frame(capture); }

    const ::bgfx::Memory* Alloc(uint32_t size) override { return ::bgfx::alloc(size); }
    const ::bgfx::Memory* Copy(const void* data, uint32_t size) override { return ::bgfx::copy(data, size); }
    const ::bgfx::Memory* MakeRef(const void* data, uint32_t size) override { return ::bgfx::makeRef(data, size); }

    void SetViewClear(uint16_t id, uint16_t flags, uint32_t rgba, float depth, uint8_t stencil) override { ::bgfx::setViewClear(id, flags, rgba, depth, stencil); }
    void SetViewRect(uint16_t id, uint16_t x, uint16_t y, uint16_t width, uint16_t height) override { ::bgfx::setViewRect(id, x, y, width, height); }
    void SetViewMode(uint16_t id, ::bgfx::ViewMode::Enum mode) override { ::bgfx::setViewMode(id, mode); }
    void SetViewTransform(uint16_t id, const void* view, const void* proj) override { ::bgfx::setViewTransform(id, view, proj); }
    void SetViewFrameBuffer(uint16_t id, ::bgfx::FrameBufferHandle handle) override { ::bgfx::setViewFrameBuffer(id, handle); }
    void Touch(uint16_t id) override { ::bgfx::touch(id); }

    ::bgfx::ShaderHandle CreateShader(const ::bgfx::Memory* mem) override { return ::bgfx::createShader(mem); }
    ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, ::bgfx::ShaderHandle fsh, bool destroyShaders) override { return ::bgfx::createProgram(vsh, fsh, destroyShaders); }
    ::bgfx::ProgramHandle CreateComputeProgram(::bgfx::ShaderHandle csh, bool destroyShaders) override { return ::bgfx::createProgram(csh, destroyShaders); }
    
    ::bgfx::VertexBufferHandle CreateVertexBuffer(const ::bgfx::Memory* mem, const ::bgfx::VertexLayout& layout) override { return ::bgfx::createVertexBuffer(mem, layout); }
    ::bgfx::IndexBufferHandle CreateIndexBuffer(const ::bgfx::Memory* mem) override { return ::bgfx::createIndexBuffer(mem); }
    ::bgfx::DynamicIndexBufferHandle CreateDynamicIndexBuffer(uint32_t num, uint16_t flags) override { return ::bgfx::createDynamicIndexBuffer(num, flags); }
    void UpdateDynamicIndexBuffer(::bgfx::DynamicIndexBufferHandle handle, uint32_t startIndex, const ::bgfx::Memory* mem) override { ::bgfx::update(handle, startIndex, mem); }

    ::bgfx::TextureHandle CreateTexture2D(uint16_t width, uint16_t height, bool hasMips, uint16_t numLayers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) override { return ::bgfx::createTexture2D(width, height, hasMips, numLayers, format, flags, mem); }
    ::bgfx::TextureHandle CreateTextureCube(uint16_t size, bool hasMips, uint16_t numLayers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) override { return ::bgfx::createTextureCube(size, hasMips, numLayers, format, flags, mem); }
    ::bgfx::FrameBufferHandle CreateFrameBuffer(uint8_t num, const ::bgfx::TextureHandle* handles, bool destroyTextures) override { return ::bgfx::createFrameBuffer(num, handles, destroyTextures); }
    ::bgfx::TextureHandle GetTexture(::bgfx::FrameBufferHandle handle, uint8_t attachment) override { return ::bgfx::getTexture(handle, attachment); }

    ::bgfx::UniformHandle CreateUniform(const char* name, ::bgfx::UniformType::Enum type, uint16_t num) override { return ::bgfx::createUniform(name, type, num); }

    void Destroy(::bgfx::ShaderHandle handle) override { ::bgfx::destroy(handle); }
    void Destroy(::bgfx::ProgramHandle handle) override { ::bgfx::destroy(handle); }
    void Destroy(::bgfx::UniformHandle handle) override { ::bgfx::destroy(handle); }
    void Destroy(::bgfx::TextureHandle handle) override { ::bgfx::destroy(handle); }
    void Destroy(::bgfx::FrameBufferHandle handle) override { ::bgfx::destroy(handle); }
    void Destroy(::bgfx::VertexBufferHandle handle) override { ::bgfx::destroy(handle); }
    void Destroy(::bgfx::IndexBufferHandle handle) override { ::bgfx::destroy(handle); }
    void Destroy(::bgfx::DynamicIndexBufferHandle handle) override { ::bgfx::destroy(handle); }

    void SetState(uint64_t state, uint32_t rgba) override { ::bgfx::setState(state, rgba); }
    void SetTransform(const void* mtx, uint16_t num) override { ::bgfx::setTransform(mtx, num); }
    void SetUniform(::bgfx::UniformHandle handle, const void* value, uint16_t num) override { ::bgfx::setUniform(handle, value, num); }
    void SetTexture(uint8_t stage, ::bgfx::UniformHandle sampler, ::bgfx::TextureHandle handle, uint32_t flags) override { ::bgfx::setTexture(stage, sampler, handle, flags); }
    void SetVertexBuffer(uint8_t stream, ::bgfx::VertexBufferHandle handle) override { ::bgfx::setVertexBuffer(stream, handle); }
    void SetIndexBuffer(::bgfx::IndexBufferHandle handle) override { ::bgfx::setIndexBuffer(handle); }
    void SetIndexBuffer(::bgfx::DynamicIndexBufferHandle handle) override { ::bgfx::setIndexBuffer(handle); }
    void SetBuffer(uint8_t stage, ::bgfx::DynamicIndexBufferHandle handle, ::bgfx::Access::Enum access) override { ::bgfx::setBuffer(stage, handle, access); }
    
    void Submit(uint16_t id, ::bgfx::ProgramHandle program, uint32_t depth, bool preserveState) override { ::bgfx::submit(id, program, depth, preserveState); }
    void Dispatch(uint16_t id, ::bgfx::ProgramHandle program, uint32_t x, uint32_t y, uint32_t z) override { ::bgfx::dispatch(id, program, x, y, z); }
    
    void SetPaletteColor(uint8_t index, float r, float g, float b, float a) override { ::bgfx::setPaletteColor(index, r, g, b, a); }
};

} // namespace kernel_engine::render::bgfx

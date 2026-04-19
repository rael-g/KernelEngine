#pragma once
#include <bgfx/bgfx.h>

namespace kernel_engine::render::bgfx {

class BgfxBackend {
 public:
  virtual ~BgfxBackend() = default;

  virtual bool Init(const ::bgfx::Init& init) = 0;
  virtual void Shutdown() = 0;
  virtual void SetViewClear(::bgfx::ViewId id, uint16_t flags, uint32_t rgba = 0, float depth = 1.0f, uint8_t stencil = 0) = 0;
  virtual void SetViewClearPalette(::bgfx::ViewId id, uint16_t flags, float depth, uint8_t stencil, uint8_t palette0 = UINT8_MAX) = 0;
  virtual void SetViewRect(::bgfx::ViewId id, uint16_t x, uint16_t y, uint16_t width, uint16_t height) = 0;
  virtual void SetViewTransform(::bgfx::ViewId id, const void* view, const void* proj) = 0;
  virtual void SetViewFrameBuffer(::bgfx::ViewId id, ::bgfx::FrameBufferHandle handle) = 0;
  virtual void SetViewMode(::bgfx::ViewId id, ::bgfx::ViewMode::Enum mode) = 0;
  virtual uint32_t Frame(bool capture = false) = 0;
  virtual void Touch(::bgfx::ViewId id) = 0;
  
  virtual ::bgfx::VertexLayoutHandle CreateVertexLayout(const ::bgfx::VertexLayout& layout) = 0;
  virtual ::bgfx::VertexBufferHandle CreateVertexBuffer(const ::bgfx::Memory* mem, const ::bgfx::VertexLayout& layout, uint16_t flags = BGFX_BUFFER_NONE) = 0;
  virtual ::bgfx::IndexBufferHandle CreateIndexBuffer(const ::bgfx::Memory* mem, uint16_t flags = BGFX_BUFFER_NONE) = 0;
  virtual ::bgfx::DynamicIndexBufferHandle CreateDynamicIndexBuffer(uint32_t num, uint16_t flags = BGFX_BUFFER_NONE) = 0;
  
  virtual ::bgfx::ShaderHandle CreateShader(const ::bgfx::Memory* mem) = 0;
  virtual ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, ::bgfx::ShaderHandle fsh, bool destroy_shaders = false) = 0;
  virtual ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, bool destroy_shader = false) = 0;
  
  virtual ::bgfx::UniformHandle CreateUniform(const char* name, ::bgfx::UniformType::Enum type, uint16_t num = 1) = 0;
  virtual ::bgfx::TextureHandle CreateTexture2D(uint16_t width, uint16_t height, bool has_mips, uint16_t num_layers, ::bgfx::TextureFormat::Enum format, uint64_t flags = BGFX_TEXTURE_NONE, const ::bgfx::Memory* mem = nullptr) = 0;
  virtual ::bgfx::TextureHandle CreateTextureCube(uint16_t size, bool has_mips, uint16_t num_layers, ::bgfx::TextureFormat::Enum format, uint64_t flags = BGFX_TEXTURE_NONE, const ::bgfx::Memory* mem = nullptr) = 0;
  virtual ::bgfx::FrameBufferHandle CreateFrameBuffer(uint8_t num, const ::bgfx::TextureHandle* handles, bool destroy_textures = false) = 0;
  
  virtual void Destroy(::bgfx::VertexBufferHandle handle) = 0;
  virtual void Destroy(::bgfx::IndexBufferHandle handle) = 0;
  virtual void Destroy(::bgfx::DynamicIndexBufferHandle handle) = 0;
  virtual void Destroy(::bgfx::ShaderHandle handle) = 0;
  virtual void Destroy(::bgfx::ProgramHandle handle) = 0;
  virtual void Destroy(::bgfx::UniformHandle handle) = 0;
  virtual void Destroy(::bgfx::TextureHandle handle) = 0;
  virtual void Destroy(::bgfx::FrameBufferHandle handle) = 0;

  virtual void SetTransform(const void* mtx, uint16_t num = 1) = 0;
  virtual void SetUniform(::bgfx::UniformHandle handle, const void* value, uint16_t num = 1) = 0;
  virtual void SetVertexBuffer(uint8_t stream, ::bgfx::VertexBufferHandle handle) = 0;
  virtual void SetIndexBuffer(::bgfx::IndexBufferHandle handle) = 0;
  virtual void SetTexture(uint8_t stage, ::bgfx::UniformHandle sampler, ::bgfx::TextureHandle handle, uint32_t flags = UINT32_MAX) = 0;
  virtual void SetBuffer(uint8_t stage, ::bgfx::DynamicIndexBufferHandle handle, ::bgfx::Access::Enum access) = 0;
  virtual void SetState(uint64_t state, uint32_t rgba = 0) = 0;
  virtual void Submit(::bgfx::ViewId id, ::bgfx::ProgramHandle handle, uint32_t depth = 0, uint8_t flags = BGFX_DISCARD_ALL) = 0;
  virtual void Dispatch(::bgfx::ViewId id, ::bgfx::ProgramHandle handle, uint32_t ngx = 1, uint32_t ngy = 1, uint32_t ngz = 1, uint8_t flags = BGFX_DISCARD_ALL) = 0;
  
  virtual const ::bgfx::Caps* GetCaps() = 0;
  virtual ::bgfx::TextureHandle GetTexture(::bgfx::FrameBufferHandle handle, uint8_t attachment = 0) = 0;
  virtual void Update(::bgfx::DynamicIndexBufferHandle handle, uint32_t start_index, const ::bgfx::Memory* mem) = 0;
  virtual void SetPaletteColor(uint8_t index, float r, float g, float b, float a) = 0;
  virtual const ::bgfx::Memory* Copy(const void* data, uint32_t size) = 0;
  virtual const ::bgfx::Memory* Alloc(uint32_t size) = 0;
};

class RealBgfxBackend : public BgfxBackend {
 public:
  bool Init(const ::bgfx::Init& init) override { return ::bgfx::init(init); }
  void Shutdown() override { ::bgfx::shutdown(); }
  void SetViewClear(::bgfx::ViewId id, uint16_t flags, uint32_t rgba, float depth, uint8_t stencil) override { ::bgfx::setViewClear(id, flags, rgba, depth, stencil); }
  void SetViewClearPalette(::bgfx::ViewId id, uint16_t flags, float depth, uint8_t stencil, uint8_t palette0) override { ::bgfx::setViewClear(id, flags, depth, stencil, palette0); }
  void SetViewRect(::bgfx::ViewId id, uint16_t x, uint16_t y, uint16_t width, uint16_t height) override { ::bgfx::setViewRect(id, x, y, width, height); }
  void SetViewTransform(::bgfx::ViewId id, const void* view, const void* proj) override { ::bgfx::setViewTransform(id, view, proj); }
  void SetViewFrameBuffer(::bgfx::ViewId id, ::bgfx::FrameBufferHandle handle) override { ::bgfx::setViewFrameBuffer(id, handle); }
  void SetViewMode(::bgfx::ViewId id, ::bgfx::ViewMode::Enum mode) override { ::bgfx::setViewMode(id, mode); }
  uint32_t Frame(bool capture) override { return ::bgfx::frame(capture); }
  void Touch(::bgfx::ViewId id) override { ::bgfx::touch(id); }
  
  ::bgfx::VertexLayoutHandle CreateVertexLayout(const ::bgfx::VertexLayout& layout) override { return ::bgfx::createVertexLayout(layout); }
  ::bgfx::VertexBufferHandle CreateVertexBuffer(const ::bgfx::Memory* mem, const ::bgfx::VertexLayout& layout, uint16_t flags) override { return ::bgfx::createVertexBuffer(mem, layout, flags); }
  ::bgfx::IndexBufferHandle CreateIndexBuffer(const ::bgfx::Memory* mem, uint16_t flags) override { return ::bgfx::createIndexBuffer(mem, flags); }
  ::bgfx::DynamicIndexBufferHandle CreateDynamicIndexBuffer(uint32_t num, uint16_t flags) override { return ::bgfx::createDynamicIndexBuffer(num, flags); }
  
  ::bgfx::ShaderHandle CreateShader(const ::bgfx::Memory* mem) override { return ::bgfx::createShader(mem); }
  ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, ::bgfx::ShaderHandle fsh, bool destroy_shaders) override { return ::bgfx::createProgram(vsh, fsh, destroy_shaders); }
  ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, bool destroy_shader) override { return ::bgfx::createProgram(vsh, destroy_shader); }
  
  ::bgfx::UniformHandle CreateUniform(const char* name, ::bgfx::UniformType::Enum type, uint16_t num) override { return ::bgfx::createUniform(name, type, num); }
  ::bgfx::TextureHandle CreateTexture2D(uint16_t width, uint16_t height, bool has_mips, uint16_t num_layers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) override { return ::bgfx::createTexture2D(width, height, has_mips, num_layers, format, flags, mem); }
  ::bgfx::TextureHandle CreateTextureCube(uint16_t size, bool has_mips, uint16_t num_layers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) override { return ::bgfx::createTextureCube(size, has_mips, num_layers, format, flags, mem); }
  ::bgfx::FrameBufferHandle CreateFrameBuffer(uint8_t num, const ::bgfx::TextureHandle* handles, bool destroy_textures) override { return ::bgfx::createFrameBuffer(num, handles, destroy_textures); }
  
  void Destroy(::bgfx::VertexBufferHandle handle) override { ::bgfx::destroy(handle); }
  void Destroy(::bgfx::IndexBufferHandle handle) override { ::bgfx::destroy(handle); }
  void Destroy(::bgfx::DynamicIndexBufferHandle handle) override { ::bgfx::destroy(handle); }
  void Destroy(::bgfx::ShaderHandle handle) override { ::bgfx::destroy(handle); }
  void Destroy(::bgfx::ProgramHandle handle) override { ::bgfx::destroy(handle); }
  void Destroy(::bgfx::UniformHandle handle) override { ::bgfx::destroy(handle); }
  void Destroy(::bgfx::TextureHandle handle) override { ::bgfx::destroy(handle); }
  void Destroy(::bgfx::FrameBufferHandle handle) override { ::bgfx::destroy(handle); }

  void SetTransform(const void* mtx, uint16_t num) override { ::bgfx::setTransform(mtx, num); }
  void SetUniform(::bgfx::UniformHandle handle, const void* value, uint16_t num) override { ::bgfx::setUniform(handle, value, num); }
  void SetVertexBuffer(uint8_t stream, ::bgfx::VertexBufferHandle handle) override { ::bgfx::setVertexBuffer(stream, handle); }
  void SetIndexBuffer(::bgfx::IndexBufferHandle handle) override { ::bgfx::setIndexBuffer(handle); }
  void SetTexture(uint8_t stage, ::bgfx::UniformHandle sampler, ::bgfx::TextureHandle handle, uint32_t flags) override { ::bgfx::setTexture(stage, sampler, handle, flags); }
  void SetBuffer(uint8_t stage, ::bgfx::DynamicIndexBufferHandle handle, ::bgfx::Access::Enum access) override { ::bgfx::setBuffer(stage, handle, access); }
  void SetState(uint64_t state, uint32_t rgba) override { ::bgfx::setState(state, rgba); }
  void Submit(::bgfx::ViewId id, ::bgfx::ProgramHandle handle, uint32_t depth, uint8_t flags) override { ::bgfx::submit(id, handle, depth, flags); }
  void Dispatch(::bgfx::ViewId id, ::bgfx::ProgramHandle handle, uint32_t ngx, uint32_t ngy, uint32_t ngz, uint8_t flags) override { ::bgfx::dispatch(id, handle, ngx, ngy, ngz, flags); }
  
  const ::bgfx::Caps* GetCaps() override { return ::bgfx::getCaps(); }
  ::bgfx::TextureHandle GetTexture(::bgfx::FrameBufferHandle handle, uint8_t attachment) override { return ::bgfx::getTexture(handle, attachment); }
  void Update(::bgfx::DynamicIndexBufferHandle handle, uint32_t start_index, const ::bgfx::Memory* mem) override { ::bgfx::update(handle, start_index, mem); }
  void SetPaletteColor(uint8_t index, float r, float g, float b, float a) override { ::bgfx::setPaletteColor(index, r, g, b, a); }
  const ::bgfx::Memory* Copy(const void* data, uint32_t size) override { return ::bgfx::copy(data, size); }
  const ::bgfx::Memory* Alloc(uint32_t size) override { return ::bgfx::alloc(size); }
};

} // namespace kernel_engine::render::bgfx

#include <gtest/gtest.h>
#include <BgfxRenderer.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/window/window.h>
#include "bgfx_interface.hh"

using namespace kernel_engine::render::bgfx;

class MockBgfxBackend : public BgfxBackend {
 public:
  bool init_ret = true;
  int frame_count = 0;
  bool Init(const ::bgfx::Init& init) override { (void)init; return init_ret; }
  void Shutdown() override {}
  void SetViewClear(::bgfx::ViewId id, uint16_t flags, uint32_t rgba, float depth, uint8_t stencil) override { (void)id; (void)flags; (void)rgba; (void)depth; (void)stencil; }
  void SetViewClearPalette(::bgfx::ViewId id, uint16_t flags, float depth, uint8_t stencil, uint8_t palette0) override { (void)id; (void)flags; (void)depth; (void)stencil; (void)palette0; }
  void SetViewRect(::bgfx::ViewId id, uint16_t x, uint16_t y, uint16_t width, uint16_t height) override { (void)id; (void)x; (void)y; (void)width; (void)height; }
  void SetViewTransform(::bgfx::ViewId id, const void* view, const void* proj) override { (void)id; (void)view; (void)proj; }
  void SetViewFrameBuffer(::bgfx::ViewId id, ::bgfx::FrameBufferHandle handle) override { (void)id; (void)handle; }
  void SetViewMode(::bgfx::ViewId id, ::bgfx::ViewMode::Enum mode) override { (void)id; (void)mode; }
  uint32_t Frame(bool capture) override { (void)capture; frame_count++; return 0; }
  void Touch(::bgfx::ViewId id) override { (void)id; }
  ::bgfx::VertexLayoutHandle CreateVertexLayout(const ::bgfx::VertexLayout& layout) override { (void)layout; return {1}; }
  ::bgfx::VertexBufferHandle CreateVertexBuffer(const ::bgfx::Memory* mem, const ::bgfx::VertexLayout& layout, uint16_t flags) override { (void)mem; (void)layout; (void)flags; return {1}; }
  ::bgfx::IndexBufferHandle CreateIndexBuffer(const ::bgfx::Memory* mem, uint16_t flags) override { (void)mem; (void)flags; return {1}; }
  ::bgfx::DynamicIndexBufferHandle CreateDynamicIndexBuffer(uint32_t num, uint16_t flags) override { (void)num; (void)flags; return {1}; }
  ::bgfx::ShaderHandle CreateShader(const ::bgfx::Memory* mem) override { (void)mem; return {1}; }
  ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, ::bgfx::ShaderHandle fsh, bool destroy_shaders) override { (void)vsh; (void)fsh; (void)destroy_shaders; return {1}; }
  ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, bool destroy_shader) override { (void)vsh; (void)destroy_shader; return {1}; }
  ::bgfx::UniformHandle CreateUniform(const char* name, ::bgfx::UniformType::Enum type, uint16_t num) override { (void)name; (void)type; (void)num; return {1}; }
  ::bgfx::TextureHandle CreateTexture2D(uint16_t width, uint16_t height, bool has_mips, uint16_t num_layers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) override { (void)width; (void)height; (void)has_mips; (void)num_layers; (void)format; (void)flags; (void)mem; return {1}; }
  ::bgfx::TextureHandle CreateTextureCube(uint16_t size, bool has_mips, uint16_t num_layers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) override { (void)size; (void)has_mips; (void)num_layers; (void)format; (void)flags; (void)mem; return {1}; }
  ::bgfx::FrameBufferHandle CreateFrameBuffer(uint8_t num, const ::bgfx::TextureHandle* handles, bool destroy_textures) override { (void)num; (void)handles; (void)destroy_textures; return {1}; }
  void Destroy(::bgfx::VertexBufferHandle handle) override { (void)handle; }
  void Destroy(::bgfx::IndexBufferHandle handle) override { (void)handle; }
  void Destroy(::bgfx::DynamicIndexBufferHandle handle) override { (void)handle; }
  void Destroy(::bgfx::ShaderHandle handle) override { (void)handle; }
  void Destroy(::bgfx::ProgramHandle handle) override { (void)handle; }
  void Destroy(::bgfx::UniformHandle handle) override { (void)handle; }
  void Destroy(::bgfx::TextureHandle handle) override { (void)handle; }
  void Destroy(::bgfx::FrameBufferHandle handle) override { (void)handle; }
  void SetTransform(const void* mtx, uint16_t num) override { (void)mtx; (void)num; }
  void SetUniform(::bgfx::UniformHandle handle, const void* value, uint16_t num) override { (void)handle; (void)value; (void)num; }
  void SetVertexBuffer(uint8_t stream, ::bgfx::VertexBufferHandle handle) override { (void)stream; (void)handle; }
  void SetIndexBuffer(::bgfx::IndexBufferHandle handle) override { (void)handle; }
  void SetTexture(uint8_t stage, ::bgfx::UniformHandle sampler, ::bgfx::TextureHandle handle, uint32_t flags) override { (void)stage; (void)sampler; (void)handle; (void)flags; }
  void SetBuffer(uint8_t stage, ::bgfx::DynamicIndexBufferHandle handle, ::bgfx::Access::Enum access) override { (void)stage; (void)handle; (void)access; }
  void SetState(uint64_t state, uint32_t rgba) override { (void)state; (void)rgba; }
  void Submit(::bgfx::ViewId id, ::bgfx::ProgramHandle handle, uint32_t depth, uint8_t flags) override { (void)id; (void)handle; (void)depth; (void)flags; }
  void Dispatch(::bgfx::ViewId id, ::bgfx::ProgramHandle handle, uint32_t ngx, uint32_t ngy, uint32_t ngz, uint8_t flags) override { (void)id; (void)handle; (void)ngx; (void)ngy; (void)ngz; (void)flags; }
  const ::bgfx::Caps* GetCaps() override { static ::bgfx::Caps caps; return &caps; }
  ::bgfx::TextureHandle GetTexture(::bgfx::FrameBufferHandle handle, uint8_t attachment) override { (void)handle; (void)attachment; return {1}; }
  void Update(::bgfx::DynamicIndexBufferHandle handle, uint32_t start_index, const ::bgfx::Memory* mem) override { (void)handle; (void)start_index; (void)mem; }
  void SetPaletteColor(uint8_t index, float r, float g, float b, float a) override { (void)index; (void)r; (void)g; (void)b; (void)a; }
  const ::bgfx::Memory* Copy(const void* data, uint32_t size) override { return ::bgfx::copy(data, size); }
  const ::bgfx::Memory* Alloc(uint32_t size) override { return ::bgfx::alloc(size); }
};

class TestRenderer : public BgfxRenderer {
public:
    using BgfxRenderer::BgfxRenderer;
protected:
    ::bgfx::ShaderHandle LoadShader(const char* name) override { (void)name; return { 1 }; }
};

class BgfxRenderMockTest : public ::testing::Test {
 protected:
  ke_allocator* alloc = nullptr;
  ke_window* window = nullptr;
  ke_logger* logger = nullptr;
  TestRenderer* render_obj = nullptr;
  MockBgfxBackend* mock_bgfx = nullptr;

  void SetUp() override {
    alloc = ke_allocator_malloc_create();
    window = (ke_window*)calloc(1, sizeof(ke_window));
    window->get_native_handle = [](ke_window* w) -> void* { (void)w; return (void*)0x1234; };
    window->get_size = [](ke_window* w, int32_t* width, int32_t* height) { (void)w; *width = 800; *height = 600; return KE_OK; };
    
    logger = (ke_logger*)calloc(1, sizeof(ke_logger));
    logger->log = [](ke_logger* s, const ke_log_event* e) { (void)s; (void)e; };

    ke_render_bgfx_params params = { alloc, logger, nullptr, window, "shaders" };
    render_obj = new TestRenderer(&params);
    mock_bgfx = new MockBgfxBackend();
    render_obj->set_bgfx(mock_bgfx);
  }

  void TearDown() override {
    if (render_obj) { render_obj->release_bgfx(); delete render_obj; }
    if (mock_bgfx) delete mock_bgfx;
    if (window) free(window);
    if (logger) free(logger);
    if (alloc) alloc->destroy(alloc);
  }
};

TEST_F(BgfxRenderMockTest, Initialize_CallsBackendInit) {
  ASSERT_EQ(render_obj->OnInitialize(), KE_OK);
}

TEST_F(BgfxRenderMockTest, Frame_CallsBackendFrame) {
  render_obj->OnInitialize();
  ASSERT_EQ(render_obj->Frame(), KE_OK);
  ASSERT_EQ(mock_bgfx->frame_count, 1);
}

TEST_F(BgfxRenderMockTest, ClearColor_Success) {
  render_obj->OnInitialize();
  ASSERT_EQ(render_obj->ClearColor(1, 0, 0, 1), KE_OK);
}

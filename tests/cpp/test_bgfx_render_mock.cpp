#include <gtest/gtest.h>
#include <kernel_engine/render/bgfx/bgfx_render_system.hh>
#include <kernel_engine/render/bgfx/bgfx_render.hh>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/window/window.h>
#include "bgfx_interface.hh"

using namespace kernel_engine::render::bgfx;

class MockBgfxBackend : public BgfxBackend {
 public:
  bool init_called = false;
  uint16_t next_handle = 1;
  ::bgfx::Caps caps{};
  int submit_count = 0;
  int set_uniform_count = 0;

  MockBgfxBackend() {
      caps.vendorId = 0x1234;
      caps.rendererType = ::bgfx::RendererType::Vulkan;
  }

  bool Init(const ::bgfx::Init& init) override { init_called = true; return true; }
  void Shutdown() override {}
  void SetViewClear(::bgfx::ViewId id, uint16_t flags, uint32_t rgba, float depth, uint8_t stencil) override {}
  void SetViewClearPalette(::bgfx::ViewId id, uint16_t flags, float depth, uint8_t stencil, uint8_t palette0) override {}
  void SetViewRect(::bgfx::ViewId id, uint16_t x, uint16_t y, uint16_t width, uint16_t height) override {}
  void SetViewTransform(::bgfx::ViewId id, const void* view, const void* proj) override {}
  void SetViewFrameBuffer(::bgfx::ViewId id, ::bgfx::FrameBufferHandle handle) override {}
  uint32_t Frame(bool capture) override { return 0; }
  void Touch(::bgfx::ViewId id) override {}
  
  ::bgfx::VertexLayoutHandle CreateVertexLayout(const ::bgfx::VertexLayout& layout) override { return {next_handle++}; }
  ::bgfx::VertexBufferHandle CreateVertexBuffer(const ::bgfx::Memory* mem, const ::bgfx::VertexLayout& layout, uint16_t flags) override { return {next_handle++}; }
  ::bgfx::IndexBufferHandle CreateIndexBuffer(const ::bgfx::Memory* mem, uint16_t flags) override { return {next_handle++}; }
  ::bgfx::DynamicIndexBufferHandle CreateDynamicIndexBuffer(uint32_t num, uint16_t flags) override { return {next_handle++}; }
  
  ::bgfx::ShaderHandle CreateShader(const ::bgfx::Memory* mem) override { return {next_handle++}; }
  ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, ::bgfx::ShaderHandle fsh, bool destroy_shaders) override { return {next_handle++}; }
  ::bgfx::ProgramHandle CreateProgram(::bgfx::ShaderHandle vsh, bool destroy_shader) override { return {next_handle++}; }
  
  ::bgfx::UniformHandle CreateUniform(const char* name, ::bgfx::UniformType::Enum type, uint16_t num) override { return {next_handle++}; }
  ::bgfx::TextureHandle CreateTexture2D(uint16_t width, uint16_t height, bool has_mips, uint16_t num_layers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) override { return {next_handle++}; }
  ::bgfx::TextureHandle CreateTextureCube(uint16_t size, bool has_mips, uint16_t num_layers, ::bgfx::TextureFormat::Enum format, uint64_t flags, const ::bgfx::Memory* mem) override { return {next_handle++}; }
  ::bgfx::FrameBufferHandle CreateFrameBuffer(uint8_t num, const ::bgfx::TextureHandle* handles, bool destroy_textures) override { return {next_handle++}; }
  
  void Destroy(::bgfx::VertexBufferHandle handle) override {}
  void Destroy(::bgfx::IndexBufferHandle handle) override {}
  void Destroy(::bgfx::DynamicIndexBufferHandle handle) override {}
  void Destroy(::bgfx::ShaderHandle handle) override {}
  void Destroy(::bgfx::ProgramHandle handle) override {}
  void Destroy(::bgfx::UniformHandle handle) override {}
  void Destroy(::bgfx::TextureHandle handle) override {}
  void Destroy(::bgfx::FrameBufferHandle handle) override {}

  void SetTransform(const void* mtx, uint16_t num) override {}
  void SetUniform(::bgfx::UniformHandle handle, const void* value, uint16_t num) override { set_uniform_count++; }
  void SetVertexBuffer(uint8_t stream, ::bgfx::VertexBufferHandle handle) override {}
  void SetIndexBuffer(::bgfx::IndexBufferHandle handle) override {}
  void SetTexture(uint8_t stage, ::bgfx::UniformHandle sampler, ::bgfx::TextureHandle handle, uint32_t flags) override {}
  void SetBuffer(uint8_t stage, ::bgfx::DynamicIndexBufferHandle handle, ::bgfx::Access::Enum access) override {}
  void SetState(uint64_t state, uint32_t rgba) override {}
  void Submit(::bgfx::ViewId id, ::bgfx::ProgramHandle handle, uint32_t depth, uint8_t flags) override { submit_count++; }
  void Dispatch(::bgfx::ViewId id, ::bgfx::ProgramHandle handle, uint32_t ngx, uint32_t ngy, uint32_t ngz, uint8_t flags) override {}
  
  const ::bgfx::Caps* GetCaps() override { return &caps; }
  ::bgfx::TextureHandle GetTexture(::bgfx::FrameBufferHandle handle, uint8_t attachment) override { return {next_handle++}; }
  void Update(::bgfx::DynamicIndexBufferHandle handle, uint32_t start_index, const ::bgfx::Memory* mem) override {}
  void SetPaletteColor(uint8_t index, float r, float g, float b, float a) override {}
};

class TestBgfxRenderSystem : public BgfxRenderSystem {
public:
    using BgfxRenderSystem::BgfxRenderSystem;
    void ForceInitialized(bool v) { 
        set_initialized(v);
        if (v) {
            set_all_handles_valid_for_test();
            skybox_vb_ = 1;
            skybox_program_ = 1;
        }
    }
protected:
    ::bgfx::ShaderHandle LoadShader(const char *name) override {
        return {1};
    }
};

class MockWindow : public ke_window {
 public:
  MockWindow() {
    this->handle = this;
    this->get_native_handle = [](ke_window* self) -> void* { return (void*)0x1234; };
    this->get_size = [](ke_window* self, int* w, int* h) -> ke_result { *w = 800; *h = 600; return KE_OK; };
  }
};

class BgfxRenderMockTest : public ::testing::Test {
 protected:
  ke_allocator* alloc = nullptr;
  MockWindow window;
  TestBgfxRenderSystem* system = nullptr;
  MockBgfxBackend* mock_bgfx = nullptr;

  void SetUp() override {
    alloc = ke_allocator_malloc_create();
    ke_render_bgfx_params params = { alloc, nullptr, nullptr, &window, "." };
    system = new TestBgfxRenderSystem(&params);
    mock_bgfx = new MockBgfxBackend();
    system->set_bgfx(mock_bgfx);

    ke_mat4 view = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
    ke_mat4 proj = {};
    proj.m[0] = 1.0f; proj.m[5] = 1.0f; 
    proj.m[10] = 1.02f; proj.m[14] = 2.02f;
    proj.m[11] = 1.0f;
    system->SetViewTransform(&view, &proj);
  }

  void TearDown() override {
    if (system) delete system;
    if (mock_bgfx) delete mock_bgfx;
    if (alloc) alloc->destroy(alloc);
  }
};

TEST_F(BgfxRenderMockTest, SetOrthographic_UpdatesInternalState) {
  ASSERT_EQ(system->SetOrthographic(1), KE_OK);
}

TEST_F(BgfxRenderMockTest, SetCameraPos_UpdatesInternalState) {
  ASSERT_EQ(system->SetCameraPos(1.0f, 2.0f, 3.0f), KE_OK);
}

TEST_F(BgfxRenderMockTest, SetClusterConfig_Works) {
  system->ForceInitialized(true);
  ke_cluster_config config = {8, 4, 12, 32, 1024};
  ASSERT_EQ(system->SetClusterConfig(&config), KE_OK);
}

TEST_F(BgfxRenderMockTest, SetSsao_SetsState) {
  ASSERT_EQ(system->SetSsao(1, 0.5f, 0.1f, 1.0f), KE_OK);
}

TEST_F(BgfxRenderMockTest, SetTonemapping_ReturnsOk) {
  system->ForceInitialized(true);
  ASSERT_EQ(system->SetTonemapping(1, 1.0f, 2.2f), KE_OK);
}

TEST_F(BgfxRenderMockTest, SetBloom_ReturnsOk) {
  system->ForceInitialized(true);
  ASSERT_EQ(system->SetBloom(1, 1.0f, 0.5f), KE_OK);
}

TEST_F(BgfxRenderMockTest, CreateShadowMap_Works) {
  ke_shadow_map_handle h;
  ASSERT_EQ(system->CreateShadowMap(512, 512, &h), KE_OK);
}

TEST_F(BgfxRenderMockTest, DestroyShadowMap_Invalid_ReturnsError) {
  ASSERT_EQ(system->DestroyShadowMap(999), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderMockTest, SubmitMesh_Minimal_ReturnsOk) {
  system->ForceInitialized(true);
  ke_mat4 trans = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
  ASSERT_EQ(system->SubmitMesh(0, 0, &trans), KE_OK);
  ASSERT_GT(mock_bgfx->submit_count, 0);
}

TEST_F(BgfxRenderMockTest, CreateCubemapRgba_Minimal_ReturnsOk) {
  // Use 2x2 to ensure mips and data size are safer
  // 6 faces * 2*2 pixels * 4 bytes = 96 bytes
  uint8_t data[96] = {0}; 
  ke_texture_handle th;
  ASSERT_EQ(system->CreateCubemapRgba(2, data, &th), KE_OK);
}

TEST_F(BgfxRenderMockTest, SubmitSkybox_Minimal_ReturnsOk) {
  system->ForceInitialized(true);
  ASSERT_EQ(system->SubmitSkybox(0), KE_OK);
}

TEST_F(BgfxRenderMockTest, C_Factory_ReturnsValidObject) {
    ke_render_bgfx_params params = { alloc, nullptr, nullptr, &window, "." };
    ke_render* render = nullptr;
    ASSERT_EQ(ke_render_bgfx_create(&params, &render), KE_OK);
    ASSERT_NE(render, nullptr);
    render->destroy(render);
}

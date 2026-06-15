#include <gtest/gtest.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/allocator/allocator.h>

class FactoryIntegrationTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
    }
};

TEST_F(FactoryIntegrationTest, RenderBgfx_Create_NullArgs_ReturnsInvalidArgument) {
    ke_render* r = nullptr;
    ASSERT_EQ(ke_render_bgfx_create(nullptr, &r), KE_ERROR_INVALID_ARGUMENT);
    
    ke_render_bgfx_params p{};
    ASSERT_EQ(ke_render_bgfx_create(&p, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(FactoryIntegrationTest, RenderBgfx_Create_NullAllocator_ReturnsInvalidArgument) {
    ke_render* r = nullptr;
    ke_render_bgfx_params p{};
    p.allocator = nullptr;
    ASSERT_EQ(ke_render_bgfx_create(&p, &r), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(FactoryIntegrationTest, WindowGlfw_Create_NullArgs_ReturnsInvalidArgument) {
    ke_window* w = nullptr;
    ASSERT_EQ(ke_window_glfw_create(nullptr, &w), KE_ERROR_INVALID_ARGUMENT);
    
    ke_window_glfw_params p{};
    ASSERT_EQ(ke_window_glfw_create(&p, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(FactoryIntegrationTest, RenderBgfx_Create_Oom_WhenDeviceAllocFails) {
    ke_allocator fa{};
    fa.alloc = +[](ke_allocator*, size_t, size_t) -> void* { return nullptr; };
    fa.free = +[](ke_allocator*, void*) {};
    
    ke_render* r = nullptr;
    ke_render_bgfx_params p{};
    p.allocator = &fa;
    ASSERT_EQ(ke_render_bgfx_create(&p, &r), KE_ERROR_OUT_OF_MEMORY);
}

TEST_F(FactoryIntegrationTest, RenderBgfx_Create_Oom_WhenRendererAllocFails) {
    static int countdown = 1;
    countdown = 1; // Success on device, fail on renderer
    ke_allocator fa{};
    fa.alloc = +[](ke_allocator*, size_t size, size_t alignment) -> void* { 
        if (countdown-- > 0) return malloc(size);
        return nullptr; 
    };
    fa.free = +[](ke_allocator*, void* p) { if(p) free(p); };
    
    ke_render* r = nullptr;
    ke_render_bgfx_params p{};
    p.allocator = &fa;
    ASSERT_EQ(ke_render_bgfx_create(&p, &r), KE_ERROR_OUT_OF_MEMORY);
}

TEST_F(FactoryIntegrationTest, WindowGlfw_Create_Oom_WhenDeviceAllocFails) {
    ke_allocator fa{};
    fa.alloc = +[](ke_allocator*, size_t, size_t) -> void* { return nullptr; };
    fa.free = +[](ke_allocator*, void*) {};
    
    ke_window* w = nullptr;
    ke_window_glfw_params p{};
    p.allocator = &fa;
    ASSERT_EQ(ke_window_glfw_create(&p, &w), KE_ERROR_OUT_OF_MEMORY);
}

#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <kernel_engine/render/bgfx/bgfx_render.hh>
#include <kernel_engine/kernel/context/allocator.h>

class BgfxRenderTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_render* renderer = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ke_render_bgfx_params params = { .allocator = alloc };
        ke_render_bgfx_create(&params, &renderer);
    }

    void TearDown() override {
        if (renderer) renderer->destroy(renderer);
        if (alloc) alloc->destroy(alloc);
    }
};

TEST_F(BgfxRenderTest, FactoryAndToApi) {
    ASSERT_NE(renderer, nullptr);
    ASSERT_NE(renderer->handle, nullptr);
}

TEST_F(BgfxRenderTest, InvalidArgs) {
    ke_mesh_handle mh;
    ASSERT_EQ(renderer->create_mesh(renderer, nullptr, 0, nullptr, 0, &mh), KE_ERROR_INVALID_ARGUMENT);
    
    ke_texture_handle th;
    ASSERT_EQ(renderer->create_texture_rgba(renderer, 0, 0, nullptr, &th), KE_ERROR_INVALID_ARGUMENT);
    
    ke_material_handle math;
    ASSERT_EQ(renderer->create_material(renderer, nullptr, &math), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, SetLights) {
    ke_directional_light light = {0,-1,0, 1,1,1, 1.0f};
    ASSERT_EQ(renderer->set_directional_light(renderer, &light), KE_OK);
    ASSERT_EQ(renderer->set_ambient_light(renderer, 0.1f, 0.1f, 0.1f), KE_OK);
}

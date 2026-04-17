#include <gtest/gtest.h>
#include <kernel_engine/render/bgfx/bgfx_render.hh>
#include <kernel_engine/kernel/context/allocator.h>

class BgfxRenderTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_render* renderer = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ke_render_bgfx_params params = { .allocator = alloc, .logger = nullptr, .window = nullptr, .shader_path = nullptr };
        ke_render_bgfx_create(&params, &renderer);
    }

    void TearDown() override {
        if (renderer) renderer->destroy(renderer);
        if (alloc) alloc->destroy(alloc);
    }
};

// --- Creation Tests ---

TEST(BgfxRenderInitTest, Create_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_render_bgfx_create(nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST(BgfxRenderInitTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_render* r = nullptr;
    ASSERT_EQ(ke_render_bgfx_create(nullptr, &r), KE_ERROR_INVALID_ARGUMENT);
}

TEST(BgfxRenderInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_render* r = nullptr;
    ke_render_bgfx_params params = { .allocator = nullptr };
    ASSERT_EQ(ke_render_bgfx_create(&params, &r), KE_ERROR_INVALID_ARGUMENT);
}

// --- Basic API Tests ---

TEST_F(BgfxRenderTest, FactoryAndToApi) {
    ASSERT_NE(renderer, nullptr);
    ASSERT_NE(renderer->handle, nullptr);
}

TEST_F(BgfxRenderTest, SetOrthographic_ReturnsOk) {
    ASSERT_EQ(renderer->set_orthographic(renderer, true), KE_OK);
}

TEST_F(BgfxRenderTest, SetCameraPos_ReturnsOk) {
    ASSERT_EQ(renderer->set_camera_pos(renderer, 10.0f, 5.0f, -2.0f), KE_OK);
}

TEST_F(BgfxRenderTest, SetAmbientLight_ReturnsOk) {
    ASSERT_EQ(renderer->set_ambient_light(renderer, 0.2f, 0.2f, 0.2f), KE_OK);
}

TEST_F(BgfxRenderTest, SetDirectionalLight_ReturnsOk) {
    ke_directional_light l = { 0, -1, 0, 1, 1, 1, 1.0f };
    ASSERT_EQ(renderer->set_directional_light(renderer, &l), KE_OK);
}

TEST_F(BgfxRenderTest, SetPointLights_NullWithCount_ReturnsError) {
    ASSERT_EQ(renderer->set_point_lights(renderer, nullptr, 1), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, SetSpotLights_NullWithCount_ReturnsError) {
    ASSERT_EQ(renderer->set_spot_lights(renderer, nullptr, 1), KE_ERROR_INVALID_ARGUMENT);
}

// --- Configuration Tests ---

TEST_F(BgfxRenderTest, SetTonemapping_FailsWithoutInit) {
    ASSERT_EQ(renderer->set_tonemapping(renderer, true, 1.0f, 2.2f), KE_ERROR_NOT_INITIALIZED);
}

TEST_F(BgfxRenderTest, SetBloom_FailsWithoutInit) {
    ASSERT_EQ(renderer->set_bloom(renderer, true, 0.8f, 1.0f), KE_ERROR_NOT_INITIALIZED);
}

TEST_F(BgfxRenderTest, ClearColor_ReturnsNotInitialized) {
    ASSERT_EQ(renderer->clear_color(renderer, 1.0f, 0.0f, 0.0f, 1.0f), KE_ERROR_NOT_INITIALIZED);
}

TEST_F(BgfxRenderTest, SetClusterConfig_ReturnsNotInitialized) {
    ke_cluster_config config = { 16, 9, 24, 64, 1024 };
    ASSERT_EQ(renderer->set_cluster_config(renderer, &config), KE_ERROR_NOT_INITIALIZED);
}

// --- Resource Tests (Failure paths without init) ---

TEST_F(BgfxRenderTest, CreateMesh_InvalidArgs_ReturnsError) {
    ke_mesh_handle h;
    ASSERT_EQ(renderer->create_mesh(renderer, nullptr, 0, nullptr, 0, &h), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, DestroyMesh_InvalidHandle_ReturnsError) {
    ASSERT_EQ(renderer->destroy_mesh(renderer, 9999), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, CreateTexture_InvalidArgs_ReturnsError) {
    ke_texture_handle h;
    ASSERT_EQ(renderer->create_texture_rgba(renderer, 0, 0, nullptr, &h), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, DestroyTexture_InvalidHandle_ReturnsError) {
    ASSERT_EQ(renderer->destroy_texture(renderer, 9999), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, CreateMaterial_NullArgs_ReturnsError) {
    ke_material_handle h;
    ASSERT_EQ(renderer->create_material(renderer, nullptr, &h), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, DestroyMaterial_InvalidHandle_ReturnsError) {
    ASSERT_EQ(renderer->destroy_material(renderer, 9999), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, SubmitMesh_NullTransform_ReturnsError) {
    ASSERT_EQ(renderer->submit_mesh(renderer, 0, 0, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(BgfxRenderTest, SubmitMesh_FailsWithoutInit) {
    ke_mat4 t;
    ASSERT_EQ(renderer->submit_mesh(renderer, 0, 0, &t), KE_ERROR_NOT_INITIALIZED);
}

// --- Destroy Tests ---

TEST_F(BgfxRenderTest, Destroy_Works) {
    renderer->destroy(renderer);
    renderer = nullptr;
    SUCCEED();
}

TEST_F(BgfxRenderTest, Destroy_NullSelf_DoesNotCrash) {
    auto destroy_fn = renderer->destroy;
    destroy_fn(nullptr);
    SUCCEED();
}

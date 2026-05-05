#include <gtest/gtest.h>
#include <lighting_manager.hpp>
#include <texture_manager.hpp>
#include <render_context.hpp>
#include <kernel_engine/kernel/common/error.h>
#include "mocks.hpp"

using namespace kernel_engine::render::bgfx;
using ::testing::_;
using ::testing::Return;
using ::testing::NiceMock;

class LightingManagerTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        manager = std::make_unique<LightingManager>();
        textures = std::make_unique<TextureManager>();
        gpu_mock = new NiceMock<MockGpuDevice>();
        ctx.gpu = gpu_mock;
    }

    void TearDown() override
    {
        delete gpu_mock;
    }

    std::unique_ptr<LightingManager> manager;
    std::unique_ptr<TextureManager> textures;
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    RenderContext ctx{};
};

TEST_F(LightingManagerTest, SetDirectionalLight_StoresColorIntensity)
{
    ke_directional_light light = { 0, -1, 0, 0, 1, 0, 3.5f }; // Green, intensity 3.5
    manager->SetDirectionalLight(&light);
    EXPECT_FLOAT_EQ(manager->light_color[1], 3.5f);
}

TEST_F(LightingManagerTest, SetPointLights_StoresCount)
{
    ke_point_light lights[2] = {};
    lights[0].intensity = 1.0f;
    lights[1].intensity = 2.0f;
    
    // Explicitly test if method exists in LightingManager
    // Note: If SetPointLights is not in LightingManager, we'll find out now
    manager->SetPointLights(lights, 2);
    EXPECT_EQ(manager->point_light_count, 2);
}

TEST_F(LightingManagerTest, SetAmbientLight_StoresRGB)
{
    manager->SetAmbientLight(0.5f, 0.6f, 0.7f);
    EXPECT_FLOAT_EQ(manager->ambient_color[2], 0.7f);
}

TEST_F(LightingManagerTest, CreateMaterial_AssignsIncrementalHandles)
{
    ke_material mat{};
    ke_material_handle h1, h2;
    manager->CreateMaterial(ctx, *textures, &mat, &h1);
    manager->CreateMaterial(ctx, *textures, &mat, &h2);
    EXPECT_EQ(h1.idx, 0);
    EXPECT_EQ(h2.idx, 1);
}

TEST_F(LightingManagerTest, GetMaterial_ReturnsInvalidForUnknownHandle)
{
    auto& entry = manager->GetMaterial({999});
    EXPECT_FALSE(entry.valid);
}

TEST_F(LightingManagerTest, SetPointLights_ClampsToCapacity)
{
    std::vector<ke_point_light> many_lights(256); 
    manager->SetPointLights(many_lights.data(), (uint32_t)many_lights.size());
    EXPECT_LE(manager->point_light_count, 128);
}

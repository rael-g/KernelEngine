#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <lighting_manager.hpp>
#include <texture_manager.hpp>
#include <render_context.hpp>
#include <gpu_device.hpp>
#include <kernel_engine/common/error.h>
#include <kernel_engine/render/frame_packet.h>
#include "mocks.hpp"

using namespace kernel_engine::render;
using namespace kernel_engine::render::core;
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
        manager.reset();
        textures.reset();
        delete gpu_mock;
    }

    std::unique_ptr<LightingManager> manager;
    std::unique_ptr<TextureManager> textures;
    NiceMock<MockGpuDevice>* gpu_mock = nullptr;
    RenderContext ctx{};
};

// ── Directional Light Tests ──────────────────────────────────────────────────

TEST_F(LightingManagerTest, SetDirectionalLight_StoresValues)
{
    ke_directional_light light = { 1, -2, 3, 0.1f, 0.2f, 0.3f, 2.0f };
    EXPECT_EQ(manager->SetDirectionalLight(&light), true);
    EXPECT_FLOAT_EQ(manager->light_dir[0], 1.0f);
    EXPECT_FLOAT_EQ(manager->light_color[0], 0.2f); // 0.1 * 2.0
}

TEST_F(LightingManagerTest, SetDirectionalLight_ReturnsError_OnNull)
{
    EXPECT_EQ(manager->SetDirectionalLight(nullptr), false);
}

// ── Ambient Light Tests ──────────────────────────────────────────────────────

TEST_F(LightingManagerTest, SetAmbientLight_ReturnsOk)
{
    EXPECT_EQ(manager->SetAmbientLight(0.1f, 0.2f, 0.3f), true);
}

TEST_F(LightingManagerTest, SetAmbientLight_StoresRed)
{
    manager->SetAmbientLight(0.1f, 0.2f, 0.3f);
    EXPECT_FLOAT_EQ(manager->ambient_color[0], 0.1f);
}

TEST_F(LightingManagerTest, SetAmbientLight_StoresGreen)
{
    manager->SetAmbientLight(0.1f, 0.2f, 0.3f);
    EXPECT_FLOAT_EQ(manager->ambient_color[1], 0.2f);
}

TEST_F(LightingManagerTest, SetAmbientLight_StoresBlue)
{
    manager->SetAmbientLight(0.1f, 0.2f, 0.3f);
    EXPECT_FLOAT_EQ(manager->ambient_color[2], 0.3f);
}

// ── Point/Spot Light Storage Tests ───────────────────────────────────────────

TEST_F(LightingManagerTest, StorePointLights_UpdatesSize)
{
    ke_point_light lights[2] = {};
    EXPECT_EQ(manager->StorePointLights(lights, 2), true);
    EXPECT_EQ(manager->GetPointLightCount(), 2);
}

TEST_F(LightingManagerTest, StoreSpotLights_UpdatesSize)
{
    ke_spot_light lights[3] = {};
    EXPECT_EQ(manager->StoreSpotLights(lights, 3), true);
    EXPECT_EQ(manager->GetSpotLightCount(), 3);
}

// ── UploadLights Tests ───────────────────────────────────────────────────────

TEST_F(LightingManagerTest, UploadLights_CallsSetUniform_ForPointLights)
{
    ke_point_light lights[1] = {};
    manager->StorePointLights(lights, 1);
    manager->point_lights_uniform = GpuUniformHandle{10};

    EXPECT_CALL(*gpu_mock, SetUniform(GpuUniformHandle{10}, _, 2)).Times(1);
    manager->UploadLights(ctx);
}

TEST_F(LightingManagerTest, UploadLights_CallsSetUniform_ForSpotLights)
{
    ke_spot_light lights[1] = {};
    manager->StoreSpotLights(lights, 1);
    manager->spot_lights_uniform = GpuUniformHandle{20};

    EXPECT_CALL(*gpu_mock, SetUniform(GpuUniformHandle{20}, _, 4)).Times(1);
    manager->UploadLights(ctx);
}

// ── RecordLights Tests ───────────────────────────────────────────────────────

TEST_F(LightingManagerTest, RecordLights_UpdatesPacket)
{
    ke_frame_packet packet{};
    packet.point_light_capacity = 10;
    packet.point_lights = (ke_point_light*)malloc(sizeof(ke_point_light) * 10);
    
    ke_point_light lights[2] = {};
    lights[0].intensity = 5.0f;

    EXPECT_EQ(manager->RecordLights(packet, lights, 2), true);
    EXPECT_EQ(packet.point_light_count, 2);
    EXPECT_FLOAT_EQ(packet.point_lights[0].intensity, 5.0f);

    free(packet.point_lights);
}

// ── Material Tests ───────────────────────────────────────────────────────────

TEST_F(LightingManagerTest, CreateMaterial_AssignsHandle)
{
    ke_material mat{};
    ke_material_handle h;
    EXPECT_EQ(manager->CreateMaterial(ctx, *textures, &mat, &h), true);
    EXPECT_EQ(h.idx, 0);
}

// Regression: an unset (idx=0) normal_map slot must be stored as KE_HANDLE_NONE
// so the runtime's ke_texture_is_valid check returns false and the shader keeps
// the vertex normal. Without this, the shader sampled handle 0 (the white
// texture) as a tangent-space normal — every face's lighting was corrupted
// (cube tops went dark in example 06, mirror reflections aimed at the wrong
// cubemap face in example 05). Caller-side handling lived in the deleted
// ResourceCommandQueue path; this owns the contract now.
TEST_F(LightingManagerTest, CreateMaterial_UnsetNormalMap_IsStoredAsNone)
{
    ke_material mat{};
    mat.normal_map.idx = 0;
    ke_material_handle h;
    manager->CreateMaterial(ctx, *textures, &mat, &h);
    EXPECT_EQ(manager->GetMaterial(h).normal_map_handle.idx, KE_HANDLE_NONE);
}

TEST_F(LightingManagerTest, CreateMaterial_UnsetNormalMap_IsInvalidTexture)
{
    ke_material mat{};
    mat.normal_map.idx = 0;
    ke_material_handle h;
    manager->CreateMaterial(ctx, *textures, &mat, &h);
    EXPECT_FALSE(ke_texture_is_valid(manager->GetMaterial(h).normal_map_handle));
}

TEST_F(LightingManagerTest, CreateMaterial_AlbedoZero_StaysUntouched)
{
    ke_material mat{};
    mat.albedo.idx = 0;
    ke_material_handle h;
    manager->CreateMaterial(ctx, *textures, &mat, &h);
    EXPECT_EQ(manager->GetMaterial(h).texture_handle.idx, 0u);
}

TEST_F(LightingManagerTest, CreateMaterial_KeepsExplicitNormalMap)
{
    ke_material mat{};
    mat.normal_map.idx = 7;
    ke_material_handle h;
    EXPECT_EQ(manager->CreateMaterial(ctx, *textures, &mat, &h), true);
    EXPECT_EQ(manager->GetMaterial(h).normal_map_handle.idx, 7u);
}

TEST_F(LightingManagerTest, DestroyMaterial_MarksInvalid)
{
    ke_material mat{};
    ke_material_handle h;
    manager->CreateMaterial(ctx, *textures, &mat, &h);
    
    EXPECT_EQ(manager->DestroyMaterial(ctx, h), true);
    EXPECT_FALSE(manager->GetMaterial(h).valid);
}

TEST_F(LightingManagerTest, StorePointLights_ReturnsError_OnNullWithCount)
{
    EXPECT_EQ(manager->StorePointLights(nullptr, 5), false);
}

TEST_F(LightingManagerTest, StoreSpotLights_ReturnsError_OnNullWithCount)
{
    EXPECT_EQ(manager->StoreSpotLights(nullptr, 5), false);
}

TEST_F(LightingManagerTest, RecordLights_ReturnsError_OnNullWithCount)
{
    ke_frame_packet packet{};
    packet.point_light_capacity = 10;
    EXPECT_EQ(manager->RecordLights(packet, nullptr, 5), false);
}

TEST_F(LightingManagerTest, RecordLights_ReturnsError_OnExceedingCapacity)
{
    ke_frame_packet packet{};
    packet.point_light_capacity = 1;
    ke_point_light lights[2] = {};
    EXPECT_EQ(manager->RecordLights(packet, lights, 2), false);
}

TEST_F(LightingManagerTest, RecordSpotLights_ReturnsError_OnExceedingCapacity)
{
    ke_frame_packet packet{};
    packet.spot_light_capacity = 1;
    ke_spot_light lights[2] = {};
    EXPECT_EQ(manager->RecordSpotLights(packet, lights, 2), false);
}

TEST_F(LightingManagerTest, UploadLights_ClampsToMaxPointLights)
{
    std::vector<ke_point_light> lights(1024); 
    manager->StorePointLights(lights.data(), (uint32_t)lights.size());
    manager->point_lights_uniform = GpuUniformHandle{10};
    manager->light_counts_uniform = GpuUniformHandle{30};

    // Should clamp to 64 and set 128 vectors (2 per light)
    EXPECT_CALL(*gpu_mock, SetUniform(GpuUniformHandle{10}, _, 128)).Times(1);
    EXPECT_CALL(*gpu_mock, SetUniform(GpuUniformHandle{30}, _, 1)).Times(1);
    manager->UploadLights(ctx);
}

TEST_F(LightingManagerTest, UploadLights_ClampsToMaxSpotLights)
{
    std::vector<ke_spot_light> lights(512); 
    manager->StoreSpotLights(lights.data(), (uint32_t)lights.size());
    manager->spot_lights_uniform = GpuUniformHandle{20};
    manager->light_counts_uniform = GpuUniformHandle{30};

    // Should clamp to 48 and set 192 vectors (4 per light)
    EXPECT_CALL(*gpu_mock, SetUniform(GpuUniformHandle{20}, _, 192)).Times(1);
    EXPECT_CALL(*gpu_mock, SetUniform(GpuUniformHandle{30}, _, 1)).Times(1);
    manager->UploadLights(ctx);
}

TEST_F(LightingManagerTest, DestroyMaterial_ReturnsError_OnInvalidHandle)
{
    EXPECT_EQ(manager->DestroyMaterial(ctx, {999}), false);
}

TEST_F(LightingManagerTest, CreateMaterial_ReturnsError_OnNullArgs)
{
    ke_material_handle h;
    EXPECT_EQ(manager->CreateMaterial(ctx, *textures, nullptr, &h), false);
    EXPECT_EQ(manager->CreateMaterial(ctx, *textures, (ke_material*)0x1, nullptr), false);
}

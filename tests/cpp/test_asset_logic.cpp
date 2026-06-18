#include <gtest/gtest.h>
#include <assimp/mesh.h>
#include <assimp/material.h>
#include <assimp/texture.h>
#include <assimp/scene.h>
#include "assimp_converter.hpp"
#include "texture_decoder.hpp"
#include <kernel_engine/allocator/allocator.h>
#include <cstdlib>
#include <cstring>
#include <vector>

using namespace kernel_engine::asset::assimp;

// ── Converter Tests ──────────────────────────────────────────────────────────

TEST(AssetLogicTest, Converter_ConvertMaterial_Success) {
    aiMaterial am;
    aiColor4D color(1.0f, 0.5f, 0.2f, 1.0f);
    am.AddProperty(&color, 1, AI_MATKEY_BASE_COLOR);

    ke_material_data md;
    int32_t albedo = -1, normal = -1;
    ke_result res = Converter::ConvertMaterial(&am, &md, &albedo, &normal);

    ASSERT_EQ(res, KE_OK);
    EXPECT_FLOAT_EQ(md.base_color_r, 1.0f);
}

TEST(AssetLogicTest, Converter_ConvertMaterial_MetallicRoughness) {
    aiMaterial am;
    float metallic = 0.8f;
    float roughness = 0.2f;
    am.AddProperty(&metallic, 1, AI_MATKEY_METALLIC_FACTOR);
    am.AddProperty(&roughness, 1, AI_MATKEY_ROUGHNESS_FACTOR);

    ke_material_data md;
    int32_t albedo = -1, normal = -1;
    ke_result res = Converter::ConvertMaterial(&am, &md, &albedo, &normal);

    ASSERT_EQ(res, KE_OK);
    EXPECT_FLOAT_EQ(md.metallic, 0.8f);
    EXPECT_FLOAT_EQ(md.roughness, 0.2f);
}

TEST(AssetLogicTest, Converter_ConvertMaterial_DiffuseFallback) {
    aiMaterial am;
    aiColor4D color(0.1f, 0.2f, 0.3f, 1.0f);
    am.AddProperty(&color, 1, AI_MATKEY_COLOR_DIFFUSE); // No base color, use diffuse

    ke_material_data md;
    int32_t albedo = -1, normal = -1;
    ke_result res = Converter::ConvertMaterial(&am, &md, &albedo, &normal);

    ASSERT_EQ(res, KE_OK);
    EXPECT_FLOAT_EQ(md.base_color_r, 0.1f);
    EXPECT_FLOAT_EQ(md.base_color_g, 0.2f);
    EXPECT_FLOAT_EQ(md.base_color_b, 0.3f);
}

TEST(AssetLogicTest, Converter_GetDirectory_Success) {
    std::string dir = Converter::GetDirectory("assets/models/car/car.obj");
    EXPECT_EQ(dir, "assets/models/car/");
}

TEST(AssetLogicTest, Converter_GetDirectory_Empty) {
    std::string dir = Converter::GetDirectory("car.obj");
    EXPECT_EQ(dir, "");
}

TEST(AssetLogicTest, Converter_ConvertMesh_Success) {
    aiMesh am;
    am.mName = "TestMesh";
    am.mNumVertices = 3;
    am.mVertices = new aiVector3D[3]{ {0,0,0}, {1,0,0}, {0,1,0} };
    am.mNumFaces = 1;
    am.mFaces = new aiFace[1];
    am.mFaces[0].mNumIndices = 3;
    am.mFaces[0].mIndices = new unsigned int[3]{ 0, 1, 2 };

    ke_mesh_data md{};
    ke_result res = Converter::ConvertMesh(&am, &md);

    ASSERT_EQ(res, KE_OK);
    EXPECT_STREQ(md.name, "TestMesh");
    EXPECT_EQ(md.vertex_count, 3);
    EXPECT_EQ(md.index_count, 3);

    ke_free(md.vertices);
    ke_free(md.indices);
}

TEST(AssetLogicTest, Converter_ConvertMaterial_Alpha) {
    aiMaterial am;
    aiColor4D color(1.0f, 1.0f, 1.0f, 0.5f);
    am.AddProperty(&color, 1, AI_MATKEY_BASE_COLOR);

    ke_material_data md;
    int32_t albedo = -1, normal = -1;
    ke_result res = Converter::ConvertMaterial(&am, &md, &albedo, &normal);

    ASSERT_EQ(res, KE_OK);
    EXPECT_FLOAT_EQ(md.base_color_a, 0.5f);
}

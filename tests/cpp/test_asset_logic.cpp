#include <gtest/gtest.h>
#include <assimp/mesh.h>
#include <assimp/material.h>
#include <assimp/texture.h>
#include <assimp/scene.h>
#include "AssimpConverter.hpp"
#include "TextureDecoder.hpp"
#include <kernel_engine/kernel/context/allocator.h>
#include <cstdlib>
#include <cstring>
#include <vector>

using namespace kernel_engine::asset::assimp;

// Use a simple allocator that works within the same binary
static void* local_alloc(ke_allocator*, size_t size, size_t) { return std::malloc(size); }
static void local_free(ke_allocator*, void* ptr) { std::free(ptr); }

class AssetLogicTest : public ::testing::Test {
protected:
    ke_allocator local_allocator{};

    void SetUp() override {
        local_allocator.alloc = local_alloc;
        local_allocator.free = local_free;
    }
};

TEST_F(AssetLogicTest, Converter_ConvertMaterial_Success) {
    aiMaterial am;
    aiColor4D color(1.0f, 0.5f, 0.2f, 1.0f);
    am.AddProperty(&color, 1, AI_MATKEY_BASE_COLOR);
    
    ke_material_data md;
    int32_t albedo = -1, normal = -1;
    ke_result res = Converter::ConvertMaterial(&am, &md, &albedo, &normal);

    ASSERT_EQ(res, KE_OK);
    EXPECT_FLOAT_EQ(md.base_color_r, 1.0f);
}

// Testing mesh conversion logic without manual pointer management for now to avoid CRT boundary issues in unit tests
TEST_F(AssetLogicTest, Converter_GetDirectory_Success) {
    std::string dir = Converter::GetDirectory("assets/models/car/car.obj");
    EXPECT_EQ(dir, "assets/models/car/");
    
    dir = Converter::GetDirectory("car.obj");
    EXPECT_EQ(dir, "");
}

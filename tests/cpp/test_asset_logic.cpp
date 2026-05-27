#include <gtest/gtest.h>
#include <assimp/mesh.h>
#include <assimp/material.h>
#include <assimp/texture.h>
#include <assimp/scene.h>
#include "assimp_converter.hpp"
#include "texture_decoder.hpp"
#include <kernel_engine/kernel/context/allocator.h>
#include <cstdlib>
#include <cstring>
#include <vector>

using namespace kernel_engine::asset::assimp;

class AssetLogicTest : public ::testing::Test {

protected:
    ke_allocator* kernel_allocator = nullptr;

    void SetUp() override {
        kernel_allocator = ke_allocator_malloc_create();
    }

    void TearDown() override {
        if (kernel_allocator) {
            kernel_allocator->destroy(kernel_allocator);
        }
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

TEST_F(AssetLogicTest, TextureDecoder_DecodeEmbedded_Raw) {
    aiTexture et;
    et.mWidth = 2;
    et.mHeight = 2;
    // Allocate pixels using the kernel allocator so it's on the same heap as the DLL
    aiTexel* pixels = (aiTexel*)kernel_allocator->alloc(kernel_allocator, sizeof(aiTexel) * 4, 0);
    for(int i=0; i<4; ++i) { pixels[i].r = 255; pixels[i].g = 0; pixels[i].b = 0; pixels[i].a = 255; }
    et.pcData = pixels;

    ke_texture_data td{};
    ke_result res = TextureDecoder::DecodeEmbedded(&et, kernel_allocator, nullptr, &td);

    ASSERT_EQ(res, KE_OK);
    EXPECT_EQ(td.width, 2);
    EXPECT_EQ(td.height, 2);
    ASSERT_NE(td.pixels, nullptr);
    EXPECT_EQ(td.pixels[0], 255);
    EXPECT_EQ(td.pixels[1], 0);

    kernel_allocator->free(kernel_allocator, td.pixels);
    // kernel_allocator->free(kernel_allocator, pixels); // REMOVED: Decoder already freed this via CopyAndFree
}


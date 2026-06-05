#include <gtest/gtest.h>
#include <kernel_engine/asset/stb_image/stb_image_loader.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <cstdlib>

class StbImageLoaderTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        alloc.alloc = [](ke_allocator*, size_t s, size_t) { return std::malloc(s); };
        alloc.free  = [](ke_allocator*, void* p) { std::free(p); };
    }

    ke_allocator alloc{};
};

TEST_F(StbImageLoaderTest, Create_ReturnsOk)
{
    ke_image_loader_stb_params params{};
    params.allocator = &alloc;
    
    ke_image_loader* loader = nullptr;
    ke_result result = ke_image_loader_stb_create(&params, &loader);
    
    ASSERT_EQ(result, KE_OK);
    ASSERT_NE(loader, nullptr);
    ASSERT_NE(loader->handle, nullptr);
    ASSERT_NE(loader->destroy, nullptr);
    ASSERT_NE(loader->load_image, nullptr);
    
    loader->destroy(loader);
}

TEST_F(StbImageLoaderTest, Create_FailsOnNullArgs)
{
    ke_image_loader* loader = nullptr;
    EXPECT_EQ(ke_image_loader_stb_create(nullptr, &loader), KE_ERROR_INVALID_ARGUMENT);
    
    ke_image_loader_stb_params params{};
    params.allocator = nullptr; // Missing allocator
    EXPECT_EQ(ke_image_loader_stb_create(&params, &loader), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(StbImageLoaderTest, LoadImage_FailsOnNullArgs)
{
    ke_image_loader_stb_params params{ .allocator = &alloc };
    ke_image_loader* loader = nullptr;
    ke_image_loader_stb_create(&params, &loader);

    ke_texture_data* data = nullptr;
    EXPECT_EQ(loader->load_image(nullptr, "path", &data), KE_ERROR_INVALID_ARGUMENT);
    EXPECT_EQ(loader->load_image(loader, nullptr, &data), KE_ERROR_INVALID_ARGUMENT);
    EXPECT_EQ(loader->load_image(loader, "path", nullptr), KE_ERROR_INVALID_ARGUMENT);

    loader->destroy(loader);
}

TEST_F(StbImageLoaderTest, FreeImage_NullData_IsSafe)
{
    ke_image_loader_stb_params params{ .allocator = &alloc };
    ke_image_loader* loader = nullptr;
    ke_image_loader_stb_create(&params, &loader);

    loader->free_image(loader, nullptr);
    loader->free_image(nullptr, nullptr);

    loader->destroy(loader);
}

TEST_F(StbImageLoaderTest, LoadImage_ValidFile_ReturnsOk)
{
    ke_image_loader_stb_params params{ .allocator = &alloc };
    ke_image_loader* loader = nullptr;
    ke_image_loader_stb_create(&params, &loader);

    const char* path = "test_image.tga";
    unsigned char tga[] = {
        0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 32, 0,
        255, 128, 64, 255 // BGRA in TGA? STB converts to RGBA
    };
    FILE* f = fopen(path, "wb");
    fwrite(tga, 1, sizeof(tga), f);
    fclose(f);

    ke_texture_data* data = nullptr;
    ke_result result = loader->load_image(loader, path, &data);
    
    ASSERT_EQ(result, KE_OK);
    ASSERT_NE(data, nullptr);
    EXPECT_EQ(data->width, 1);
    EXPECT_EQ(data->height, 1);
    EXPECT_NE(data->pixels, nullptr);
    
    loader->free_image(loader, data);
    loader->destroy(loader);
    remove(path);
}

TEST_F(StbImageLoaderTest, LoadImage_NonExistentFile_ReturnsNotFound)
{
    ke_image_loader_stb_params params{ .allocator = &alloc };
    ke_image_loader* loader = nullptr;
    ke_image_loader_stb_create(&params, &loader);
    
    ke_texture_data* data = nullptr;
    ke_result result = loader->load_image(loader, "missing.png", &data);
    
    ASSERT_EQ(result, KE_ERROR_NOT_FOUND);
    loader->destroy(loader);
}

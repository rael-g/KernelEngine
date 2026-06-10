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

TEST_F(StbImageLoaderTest, LoadImage_ReturnsOom_WhenAllocFails)
{
    // Use an allocator that fails after some successful calls
    static int countdown = 5;
    countdown = 5;
    ke_allocator fa{};
    fa.alloc = [](ke_allocator*, size_t size, size_t alignment) -> void* { 
        if (countdown > 0) { countdown--; return malloc(size); }
        return nullptr; 
    };
    fa.free  = [](ke_allocator*, void* p) { if(p) free(p); };
    
    ke_image_loader_stb_params params{ .allocator = &fa };
    ke_image_loader* loader = nullptr;
    if (ke_image_loader_stb_create(&params, &loader) == KE_OK && loader) {
        const char* path = "test_oom.tga";
        unsigned char tga[] = { 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 32, 0, 255, 255, 255, 255 };
        FILE* f = fopen(path, "wb");
        if (f) {
            fwrite(tga, 1, sizeof(tga), f);
            fclose(f);

            ke_texture_data* data = nullptr;
            countdown = 0; // Next alloc fails
            ke_result res = loader->load_image(loader, path, &data);
            EXPECT_EQ(res, KE_ERROR_OUT_OF_MEMORY);
            
            remove(path);
        }
        loader->destroy(loader);
    }
}

TEST_F(StbImageLoaderTest, Destroy_NullSelf_IsSafe)
{
    ke_image_loader_stb_params params{ .allocator = &alloc };
    ke_image_loader* loader = nullptr;
    ke_image_loader_stb_create(&params, &loader);
    auto d = loader->destroy;
    loader->destroy(loader);
    d(nullptr);
}

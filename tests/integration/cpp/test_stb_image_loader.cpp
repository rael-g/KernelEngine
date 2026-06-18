#include <gtest/gtest.h>
#include <kernel_engine/asset/stb_image/stb_image_loader.h>
#include <kernel_engine/allocator/allocator.h>
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
    
    ke_image_loader_handle loaderh{};
    ke_result result = ke_image_loader_stb_create(&params, &loaderh, nullptr);
    ke_image_loader* loader = loaderh.ref;

    ASSERT_EQ(result, KE_OK);
    ASSERT_NE(loader, nullptr);
    ASSERT_NE(loader->handle, nullptr);
    ASSERT_NE(loaderh.destroy, nullptr);
    ASSERT_NE(loader->load_image, nullptr);

    loaderh.destroy(loaderh.ref);
}

TEST_F(StbImageLoaderTest, Create_FailsOnNullArgs)
{
    ke_image_loader_handle loader{};
    EXPECT_EQ(ke_image_loader_stb_create(nullptr, &loader, nullptr), KE_ERROR);

    ke_image_loader_stb_params params{};
    params.allocator = nullptr; // Missing allocator
    EXPECT_EQ(ke_image_loader_stb_create(&params, &loader, nullptr), KE_ERROR);
}

TEST_F(StbImageLoaderTest, LoadImage_FailsOnNullArgs)
{
    ke_image_loader_stb_params params{ .allocator = &alloc };
    ke_image_loader_handle loaderh{};
    ke_image_loader_stb_create(&params, &loaderh, nullptr);
    ke_image_loader* loader = loaderh.ref;

    ke_texture_data* data = nullptr;
    EXPECT_EQ(loader->load_image(nullptr, "path", &data, nullptr), KE_ERROR);
    EXPECT_EQ(loader->load_image(loader, nullptr, &data, nullptr), KE_ERROR);
    EXPECT_EQ(loader->load_image(loader, "path", nullptr, nullptr), KE_ERROR);

    loaderh.destroy(loaderh.ref);
}

TEST_F(StbImageLoaderTest, FreeImage_NullData_IsSafe)
{
    ke_image_loader_stb_params params{ .allocator = &alloc };
    ke_image_loader_handle loaderh{};
    ke_image_loader_stb_create(&params, &loaderh, nullptr);
    ke_image_loader* loader = loaderh.ref;

    loader->free_image(loader, nullptr);
    loader->free_image(nullptr, nullptr);

    loaderh.destroy(loaderh.ref);
}

TEST_F(StbImageLoaderTest, LoadImage_ValidFile_ReturnsOk)
{
    ke_image_loader_stb_params params{ .allocator = &alloc };
    ke_image_loader_handle loaderh{};
    ke_image_loader_stb_create(&params, &loaderh, nullptr);
    ke_image_loader* loader = loaderh.ref;

    const char* path = "test_image.tga";
    unsigned char tga[] = {
        0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 32, 0,
        255, 128, 64, 255 // BGRA in TGA? STB converts to RGBA
    };
    FILE* f = fopen(path, "wb");
    fwrite(tga, 1, sizeof(tga), f);
    fclose(f);

    ke_texture_data* data = nullptr;
    ke_result result = loader->load_image(loader, path, &data, nullptr);
    
    ASSERT_EQ(result, KE_OK);
    ASSERT_NE(data, nullptr);
    EXPECT_EQ(data->width, 1);
    EXPECT_EQ(data->height, 1);
    EXPECT_NE(data->pixels, nullptr);
    
    loader->free_image(loader, data);
    loaderh.destroy(loaderh.ref);
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
    ke_image_loader_handle loaderh{};
    if (ke_image_loader_stb_create(&params, &loaderh, nullptr) == KE_OK && loaderh.ref) {
        ke_image_loader* loader = loaderh.ref;
        const char* path = "test_oom.tga";
        unsigned char tga[] = { 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 32, 0, 255, 255, 255, 255 };
        FILE* f = fopen(path, "wb");
        if (f) {
            fwrite(tga, 1, sizeof(tga), f);
            fclose(f);

            ke_texture_data* data = nullptr;
            countdown = 0; // Next alloc fails
            ke_result res = loader->load_image(loader, path, &data, nullptr);
            EXPECT_EQ(res, KE_ERROR);
            
            remove(path);
        }
        loaderh.destroy(loaderh.ref);
    }
}

TEST_F(StbImageLoaderTest, Destroy_NullSelf_IsSafe)
{
    ke_image_loader_stb_params params{ .allocator = &alloc };
    ke_image_loader_handle loaderh{};
    ke_image_loader_stb_create(&params, &loaderh, nullptr);
    auto d = loaderh.destroy;
    loaderh.destroy(loaderh.ref);
    d(nullptr);
}

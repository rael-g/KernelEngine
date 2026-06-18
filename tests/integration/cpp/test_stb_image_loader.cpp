#include <gtest/gtest.h>
#include <kernel_engine/asset/stb_image/stb_image_loader.h>
#include <cstdlib>

TEST(StbImageLoaderTest, Create_ReturnsOk)
{
    ke_image_loader_stb_params params{};

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

TEST(StbImageLoaderTest, Create_FailsOnNullArgs)
{
    ke_image_loader_handle loader{};
    EXPECT_EQ(ke_image_loader_stb_create(nullptr, &loader, nullptr), KE_ERROR);
}

TEST(StbImageLoaderTest, LoadImage_FailsOnNullArgs)
{
    ke_image_loader_stb_params params{};
    ke_image_loader_handle loaderh{};
    ke_image_loader_stb_create(&params, &loaderh, nullptr);
    ke_image_loader* loader = loaderh.ref;

    ke_texture_data* data = nullptr;
    EXPECT_EQ(loader->load_image(nullptr, "path", &data, nullptr), KE_ERROR);
    EXPECT_EQ(loader->load_image(loader, nullptr, &data, nullptr), KE_ERROR);
    EXPECT_EQ(loader->load_image(loader, "path", nullptr, nullptr), KE_ERROR);

    loaderh.destroy(loaderh.ref);
}

TEST(StbImageLoaderTest, FreeImage_NullData_IsSafe)
{
    ke_image_loader_stb_params params{};
    ke_image_loader_handle loaderh{};
    ke_image_loader_stb_create(&params, &loaderh, nullptr);
    ke_image_loader* loader = loaderh.ref;

    loader->free_image(loader, nullptr);
    loader->free_image(nullptr, nullptr);

    loaderh.destroy(loaderh.ref);
}

TEST(StbImageLoaderTest, LoadImage_ValidFile_ReturnsOk)
{
    ke_image_loader_stb_params params{};
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

TEST(StbImageLoaderTest, Destroy_NullSelf_IsSafe)
{
    ke_image_loader_stb_params params{};
    ke_image_loader_handle loaderh{};
    ke_image_loader_stb_create(&params, &loaderh, nullptr);
    auto d = loaderh.destroy;
    loaderh.destroy(loaderh.ref);
    d(nullptr);
}

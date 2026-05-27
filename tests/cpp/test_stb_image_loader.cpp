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

TEST_F(StbImageLoaderTest, LoadImage_NonExistentFile_ReturnsNotFound)
{
    ke_image_loader_stb_params params{};
    params.allocator = &alloc;
    ke_image_loader* loader = nullptr;
    ke_image_loader_stb_create(&params, &loader);
    
    ke_texture_data* data = nullptr;
    ke_result result = loader->load_image(loader, "non_existent.png", &data);
    
    ASSERT_EQ(result, KE_ERROR_NOT_FOUND);
    ASSERT_EQ(data, nullptr);
    
    loader->destroy(loader);
}

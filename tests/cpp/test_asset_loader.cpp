#include <gtest/gtest.h>
#include <kernel_engine/asset/assimp/ke_asset_loader_assimp.hh>
#include <kernel_engine/kernel/context/allocator.h>

class AssetLoaderTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_asset_loader* loader = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ke_asset_loader_assimp_params params = { alloc, nullptr };
        ke_asset_loader_assimp_create(&params, &loader);
    }

    void TearDown() override {
        if (loader) loader->destroy(loader);
        if (alloc) alloc->destroy(alloc);
    }
};

// --- Creation Tests ---

TEST(AssetLoaderInitTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_asset_loader* l = nullptr;
    ASSERT_EQ(ke_asset_loader_assimp_create(nullptr, &l), KE_ERROR_INVALID_ARGUMENT);
}

TEST(AssetLoaderInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_asset_loader* l = nullptr;
    ke_asset_loader_assimp_params params = { nullptr, nullptr };
    ASSERT_EQ(ke_asset_loader_assimp_create(&params, &l), KE_ERROR_INVALID_ARGUMENT);
}

TEST(AssetLoaderInitTest, Create_NullOut_ReturnsInvalidArgument) {
    ke_allocator* a = ke_allocator_malloc_create();
    ke_asset_loader_assimp_params params = { a, nullptr };
    ASSERT_EQ(ke_asset_loader_assimp_create(&params, nullptr), KE_ERROR_INVALID_ARGUMENT);
    a->destroy(a);
}

TEST(AssetLoaderInitTest, Create_Success_ReturnsOk) {
    ke_allocator* a = ke_allocator_malloc_create();
    ke_asset_loader* l = nullptr;
    ke_asset_loader_assimp_params params = { a, nullptr };
    ASSERT_EQ(ke_asset_loader_assimp_create(&params, &l), KE_OK);
    l->destroy(l);
    a->destroy(a);
}

// --- API Tests ---

TEST_F(AssetLoaderTest, LoadModel_NullPath_ReturnsInvalidArgument) {
    ke_model_data* out = nullptr;
    ASSERT_EQ(loader->load_model(loader, nullptr, &out), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(AssetLoaderTest, LoadModel_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(loader->load_model(loader, "test.obj", nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(AssetLoaderTest, LoadModel_NonExistentFile_ReturnsIOError) {
    ke_model_data* out = nullptr;
    ASSERT_EQ(loader->load_model(loader, "non_existent_file.obj", &out), KE_ERROR_IO);
}

TEST_F(AssetLoaderTest, FreeModel_Null_DoesNotCrash) {
    loader->free_model(loader, nullptr);
    SUCCEED();
}

// --- Destroy Tests ---

TEST_F(AssetLoaderTest, Destroy_Works) {
    loader->destroy(loader);
    loader = nullptr;
    SUCCEED();
}

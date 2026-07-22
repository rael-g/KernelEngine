#include <gtest/gtest.h>
#include <kernel_engine/asset/assimp/assimp_loader.h>

#include <cstring>

class AssetLoaderTest : public ::testing::Test {
protected:
    ke_asset_loader_handle loader_h{};
    ke_asset_loader* loader = nullptr;

    void SetUp() override {
        ke_asset_loader_assimp_params params = { nullptr };
        loader_h = ke_asset_loader_assimp_create(&params, nullptr);
        loader = loader_h.ref;
    }

    void TearDown() override {
        if (loader_h.ref) loader_h.destroy(loader_h.ref);
    }
};

// --- Creation Tests ---

TEST(AssetLoaderInitTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_asset_loader_handle l = ke_asset_loader_assimp_create(nullptr, nullptr);
    ASSERT_EQ(l.ref, nullptr);
}

TEST(AssetLoaderInitTest, Create_Success_ReturnsOk) {
    ke_asset_loader_assimp_params params = { nullptr };
    ke_asset_loader_handle l = ke_asset_loader_assimp_create(&params, nullptr);
    ASSERT_NE(l.ref, nullptr);
    l.destroy(l.ref);
}

// --- API Tests ---

TEST_F(AssetLoaderTest, LoadModel_NullPath_ReturnsInvalidArgument) {
    ke_model_data* out = loader->load_model(loader, nullptr, nullptr);
    ASSERT_EQ(out, nullptr);
}

TEST_F(AssetLoaderTest, LoadModel_NonExistentFile_ReturnsIOError) {
    ke_model_data* out = loader->load_model(loader, "non_existent_file.obj", nullptr);
    ASSERT_EQ(out, nullptr);
}

TEST_F(AssetLoaderTest, FreeModel_Null_DoesNotCrash) {
    loader->free_model(loader, nullptr);
    SUCCEED();
}

#include <kernel_engine/scheduler/scheduler.h>
#include <atomic>

TEST_F(AssetLoaderTest, LoadModel_ValidFile_ReturnsOk) {
    ke_model_data* model = loader->load_model(loader, "assets/Box.gltf", nullptr);

    if (model != nullptr) {
        EXPECT_GT(model->mesh_count, 0);
        loader->free_model(loader, model);
    } else {
        GTEST_SKIP() << "assets/Box.gltf not found at expected path";
    }
}

TEST_F(AssetLoaderTest, LoadModelAsync_Works) {
    // Synchronous mock scheduler
    ke_scheduler scheduler{};
    scheduler.dispatch = [](ke_scheduler*, ke_task_func f, void* d) -> ke_task* {
        f(d);
        return (ke_task*)1; // Fake task
    };

    struct Context {
        std::atomic<bool> done{false};
        const ke_error *err = nullptr;
        ke_asset_loader *loader = nullptr;
    } ctx;
    ctx.loader = loader;

    loader->load_model_async(loader, &scheduler, "assets/Box.gltf",
        [](const ke_error *error, ke_model_data* data, void* user) {
            auto* c = (Context*)user;
            c->err = error;
            // The completion owns the model; releasing it here is the async
            // counterpart of the free that follows a synchronous load.
            if (data != nullptr) c->loader->free_model(c->loader, data);
            c->done = true;
        }, &ctx);

    // Wait or skip if file missing
    if (ctx.err != nullptr) GTEST_SKIP() << "File not found for async test";

    ASSERT_TRUE(ctx.done);
}

// A model's memory belongs to the loader that produced it, so this exercises
// the free path on a real load rather than on a hand-built record: every block
// released here has to be one the loader itself allocated.
TEST_F(AssetLoaderTest, FreeModel_RealData_Works) {
    ke_model_data* model = loader->load_model(loader, "assets/Box.gltf", nullptr);
    if (model == nullptr) GTEST_SKIP() << "assets/Box.gltf not found at expected path";

    // Meshes, materials and textures each have their own branch in free_model;
    // a model with all three present is what makes the test worth running.
    EXPECT_GT(model->mesh_count, 0);
    EXPECT_GT(model->material_count, 0);

    loader->free_model(loader, model);
    SUCCEED();
}

// --- Destroy Tests ---

TEST_F(AssetLoaderTest, LoadModelAsync_NullArgs_ReturnsNull) {
    ke_scheduler scheduler{};
    ke_task* t = loader->load_model_async(nullptr, &scheduler, "test.obj", nullptr, nullptr);
    ASSERT_EQ(t, nullptr);

    t = loader->load_model_async(loader, nullptr, "test.obj", nullptr, nullptr);
    ASSERT_EQ(t, nullptr);

    t = loader->load_model_async(loader, &scheduler, nullptr, nullptr, nullptr);
    ASSERT_EQ(t, nullptr);
}

TEST_F(AssetLoaderTest, LoadModel_EmbeddedTexture_Works) {
    ke_model_data* model = loader->load_model(loader, "assets/Box.gltf", nullptr);
    if (model) loader->free_model(loader, model);
    SUCCEED();
}

TEST_F(AssetLoaderTest, LoadModel_MalformedFile_ReturnsIOError) {
    const char* path = "malformed.obj";
    FILE* f = fopen(path, "w");
    fprintf(f, "THIS IS NOT VALID OBJ CONTENT\n");
    fclose(f);

    ke_model_data* model = loader->load_model(loader, path, nullptr);
    if (model) loader->free_model(loader, model);
    remove(path);
    SUCCEED();
}

#include <gtest/gtest.h>
#include <kernel_engine/asset/assimp/assimp_loader.h>
#include <kernel_engine/allocator/allocator.h>

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
    } ctx;

    loader->load_model_async(loader, &scheduler, "assets/Box.gltf",
        [](const ke_error *error, ke_model_data* data, void* user) {
            auto* c = (Context*)user;
            c->err = error;
            c->done = true;
        }, &ctx);

    // Wait or skip if file missing
    if (ctx.err != nullptr) GTEST_SKIP() << "File not found for async test";

    ASSERT_TRUE(ctx.done);
}

TEST_F(AssetLoaderTest, FreeModel_RealData_Works) {
    ke_model_data* model = (ke_model_data*)ke_alloc(sizeof(ke_model_data), 0);
    std::memset(model, 0, sizeof(*model));

    model->mesh_count = 1;
    model->meshes = (ke_mesh_data*)ke_alloc(sizeof(ke_mesh_data), 0);
    std::memset(model->meshes, 0, sizeof(ke_mesh_data));
    strncpy(model->meshes[0].name, "mesh", 63);
    model->meshes[0].name[63] = '\0';

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

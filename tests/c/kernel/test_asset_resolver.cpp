#include <gtest/gtest.h>
#include <kernel_engine/framework/asset_resolver.h>
#include <kernel_engine/kernel/asset/image_loader.h>
#include <kernel_engine/kernel/asset/mesh_data.h>
#include <kernel_engine/kernel/context/allocator.h>

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

namespace fs = std::filesystem;

// ── Mock image loader ────────────────────────────────────────────────────────
//
// Records every load_image call so tests can assert the resolver dispatched
// correctly. Returns a tiny zeroed RGBA8 buffer so the contract works
// end-to-end without depending on stb_image.

struct MockImageLoader
{
    ke_image_loader  api{};
    std::string      last_path;
    int              load_count = 0;
    int              free_count = 0;
};

static ke_result MockLoadImage(ke_image_loader *self, const char *path, ke_texture_data **out)
{
    auto *m = static_cast<MockImageLoader *>(self->handle);
    m->last_path = path;
    m->load_count++;
    auto *data = static_cast<ke_texture_data *>(std::calloc(1, sizeof(ke_texture_data)));
    data->width  = 2;
    data->height = 2;
    data->pixels = static_cast<uint8_t *>(std::calloc(16, 1));
    *out = data;
    return KE_OK;
}

static void MockFreeImage(ke_image_loader *self, ke_texture_data *data)
{
    auto *m = static_cast<MockImageLoader *>(self->handle);
    m->free_count++;
    if (data) {
        std::free(data->pixels);
        std::free(data);
    }
}

static void MockDestroy(ke_image_loader *) {}

static void InitMockLoader(MockImageLoader &m)
{
    m.api.handle      = &m;
    m.api.load_image  = MockLoadImage;
    m.api.free_image  = MockFreeImage;
    m.api.destroy     = MockDestroy;
}

static fs::path WriteTempFile(const std::string &suffix, const std::string &content = "x")
{
    auto path = fs::temp_directory_path() /
                (std::string("ke_asset_resolver_test_") + std::to_string(::rand()) + suffix);
    std::ofstream(path) << content;
    return path;
}

// ── Fixture ──────────────────────────────────────────────────────────────────

class AssetResolverTest : public ::testing::Test
{
protected:
    ke_allocator      *alloc       = nullptr;
    MockImageLoader    loader;
    ke_asset_resolver *resolver    = nullptr;
    fs::path           project_root;

    void SetUp() override
    {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        InitMockLoader(loader);
        project_root = fs::temp_directory_path();
        ASSERT_EQ(ke_asset_resolver_create(alloc, &loader.api, project_root.string().c_str(),
                                            &resolver),
                  KE_OK);
    }

    void TearDown() override
    {
        if (resolver) resolver->destroy(resolver);
    }
};

// ── Texture resolution ──────────────────────────────────────────────────────

TEST_F(AssetResolverTest, ResolveTexture_AbsolutePath_DispatchesToLoader)
{
    auto img = WriteTempFile(".png");
    ke_texture_data *data = nullptr;
    EXPECT_EQ(resolver->resolve_texture(resolver, img.string().c_str(), &data), KE_OK);
    EXPECT_NE(data, nullptr);
    EXPECT_EQ(loader.load_count, 1);
    EXPECT_EQ(loader.last_path, img.string());
    resolver->free_texture(resolver, data);
    EXPECT_EQ(loader.free_count, 1);
    fs::remove(img);
}

TEST_F(AssetResolverTest, ResolveTexture_ResPrefix_JoinsProjectRoot)
{
    auto img = WriteTempFile(".png"); // already lives under temp_directory_path() == project_root
    // Build the res:// reference relative to the project root.
    auto resref = "res://" + img.filename().string();
    ke_texture_data *data = nullptr;
    EXPECT_EQ(resolver->resolve_texture(resolver, resref.c_str(), &data), KE_OK);
    EXPECT_EQ(loader.last_path, img.string());
    resolver->free_texture(resolver, data);
    fs::remove(img);
}

TEST_F(AssetResolverTest, ResolveTexture_MissingFile_ReturnsNotFound)
{
    ke_texture_data *data = nullptr;
    EXPECT_EQ(resolver->resolve_texture(resolver, "C:/this/does/not/exist.png", &data),
              KE_ERROR_NOT_FOUND);
    EXPECT_EQ(loader.load_count, 0);
}

TEST_F(AssetResolverTest, ResolveTexture_NoLoader_ReturnsInvalidArgument)
{
    ke_asset_resolver *r = nullptr;
    ASSERT_EQ(ke_asset_resolver_create(alloc, nullptr, nullptr, &r), KE_OK);
    ke_texture_data *data = nullptr;
    EXPECT_EQ(r->resolve_texture(r, "anything.png", &data), KE_ERROR_INVALID_ARGUMENT);
    r->destroy(r);
}

// ── Mesh resolution ─────────────────────────────────────────────────────────

TEST_F(AssetResolverTest, ResolveMesh_PrimitiveCube_BakesViaMeshShape)
{
    ke_mesh_shape_data data{};
    EXPECT_EQ(resolver->resolve_mesh(resolver, "res://primitives/cube", &data), KE_OK);
    EXPECT_EQ(data.vertex_count, 24u);
    EXPECT_EQ(data.index_count,  36u);
    resolver->free_mesh(resolver, &data);
}

TEST_F(AssetResolverTest, ResolveMesh_PrimitiveSphere_BakesViaMeshShape)
{
    ke_mesh_shape_data data{};
    EXPECT_EQ(resolver->resolve_mesh(resolver, "res://primitives/sphere", &data), KE_OK);
    EXPECT_GT(data.vertex_count, 0u);
    resolver->free_mesh(resolver, &data);
}

TEST_F(AssetResolverTest, ResolveMesh_UnknownPrimitive_ReturnsNotFound)
{
    ke_mesh_shape_data data{};
    EXPECT_EQ(resolver->resolve_mesh(resolver, "res://primitives/teapot", &data),
              KE_ERROR_NOT_FOUND);
}

// ── Material resolution ────────────────────────────────────────────────────

TEST_F(AssetResolverTest, ResolveMaterial_ResPrefix_ParsesViaMaterialFile)
{
    auto mat = WriteTempFile(".material",
                              "[material]\nbase_color = [0.1, 0.2, 0.3, 1.0]\n");
    auto resref = "res://" + mat.filename().string();
    ke_material_spec spec{};
    EXPECT_EQ(resolver->resolve_material(resolver, resref.c_str(), &spec), KE_OK);
    EXPECT_FLOAT_EQ(spec.base_color[0], 0.1f);
    fs::remove(mat);
}

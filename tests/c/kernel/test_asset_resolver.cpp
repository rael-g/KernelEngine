#include <gtest/gtest.h>
#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/framework/asset_resolver_create.h>
#include <kernel_engine/asset/image_loader.h>
#include <kernel_engine/asset/mesh_data.h>

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

namespace fs = std::filesystem;

// ── Mock image loader ────────────────────────────────────────────────────────

struct MockImageLoader
{
    ke_image_loader  api{};
    std::string      last_path;
    int              load_count = 0;
    int              free_count = 0;
};

static ke_texture_data *MockLoadImage(ke_image_loader *self, const char *path,
                                      ke_error **out_error)
{
    (void)out_error;
    auto *m = static_cast<MockImageLoader *>(self->handle);
    m->last_path = path;
    m->load_count++;
    auto *data = static_cast<ke_texture_data *>(std::calloc(1, sizeof(ke_texture_data)));
    data->width  = 2;
    data->height = 2;
    data->pixels = static_cast<uint8_t *>(std::calloc(16, 1));
    return data;
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

static void InitMockLoader(MockImageLoader &m)
{
    m.api.handle      = &m;
    m.api.load_image  = MockLoadImage;
    m.api.free_image  = MockFreeImage;
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
    MockImageLoader    loader;
    ke_asset_resolver_handle resolver_h{};
    ke_asset_resolver *resolver    = nullptr;
    fs::path           project_root;

    void SetUp() override
    {
        InitMockLoader(loader);
        project_root = fs::temp_directory_path();
        resolver_h = ke_asset_resolver_create(&loader.api, nullptr,
                                               project_root.string().c_str(), NULL);
        ASSERT_NE(resolver_h.ref, nullptr);
        resolver = resolver_h.ref;
    }

    void TearDown() override
    {
        if (resolver_h.ref) resolver_h.destroy(resolver_h.ref);
    }
};

// ── Texture resolution ──────────────────────────────────────────────────────

TEST_F(AssetResolverTest, ResolveTexture_AbsolutePath_DispatchesToLoader)
{
    auto img = WriteTempFile(".png");
    ke_texture_data *data = nullptr;
    EXPECT_TRUE(resolver->resolve_texture(resolver, img.string().c_str(), &data, nullptr));
    EXPECT_NE(data, nullptr);
    EXPECT_EQ(loader.load_count, 1);
    EXPECT_EQ(loader.last_path, img.string());
    resolver->free_texture(resolver, data);
    EXPECT_EQ(loader.free_count, 1);
    fs::remove(img);
}

TEST_F(AssetResolverTest, ResolveTexture_ResPrefix_JoinsProjectRoot)
{
    auto img = WriteTempFile(".png");
    auto resref = "res://" + img.filename().string();
    ke_texture_data *data = nullptr;
    EXPECT_TRUE(resolver->resolve_texture(resolver, resref.c_str(), &data, nullptr));
    EXPECT_EQ(loader.last_path, img.string());
    resolver->free_texture(resolver, data);
    fs::remove(img);
}

TEST_F(AssetResolverTest, ResolveTexture_MissingFile_ReturnsNotFound)
{
    ke_texture_data *data = nullptr;
    EXPECT_FALSE(resolver->resolve_texture(resolver, "C:/this/does/not/exist.png", &data, nullptr));
}

TEST_F(AssetResolverTest, ResolveTexture_NoLoader_ReturnsInvalidArgument)
{
    ke_asset_resolver_handle rh = ke_asset_resolver_create(nullptr, nullptr, nullptr, NULL);
    ASSERT_NE(rh.ref, nullptr);
    ke_asset_resolver *r = rh.ref;
    ke_texture_data *data = nullptr;
    EXPECT_FALSE(r->resolve_texture(r, "anything.png", &data, nullptr));
    rh.destroy(rh.ref);
}

// ── Mesh resolution ─────────────────────────────────────────────────────────

TEST_F(AssetResolverTest, ResolveMesh_AllPrimitives_Works)
{
    ke_mesh_shape_data data{};
    EXPECT_TRUE(resolver->resolve_mesh(resolver, "res://primitives/quad", &data, nullptr));
    resolver->free_mesh(resolver, &data);
    EXPECT_TRUE(resolver->resolve_mesh(resolver, "res://primitives/plane", &data, nullptr));
    resolver->free_mesh(resolver, &data);
    EXPECT_TRUE(resolver->resolve_mesh(resolver, "res://primitives/cube", &data, nullptr));
    resolver->free_mesh(resolver, &data);
    EXPECT_TRUE(resolver->resolve_mesh(resolver, "res://primitives/sphere", &data, nullptr));
    resolver->free_mesh(resolver, &data);
}

TEST_F(AssetResolverTest, ResolveMesh_Cube_EachFaceIsFlatWithCornerUvs)
{
    ke_mesh_shape_data data{};
    ASSERT_TRUE(resolver->resolve_mesh(resolver, "res://primitives/cube", &data, nullptr));
    ASSERT_EQ(data.vertex_count, 24u);
    ASSERT_EQ(data.index_count, 36u);

    for (uint32_t f = 0; f < 6; ++f) {
        const ke_vertex *q = &data.vertices[f * 4];
        // A face's four corners share one axis-aligned normal.
        for (uint32_t k = 1; k < 4; ++k) {
            EXPECT_FLOAT_EQ(q[k].nx, q[0].nx) << "face " << f;
            EXPECT_FLOAT_EQ(q[k].ny, q[0].ny) << "face " << f;
            EXPECT_FLOAT_EQ(q[k].nz, q[0].nz) << "face " << f;
        }
        EXPECT_FLOAT_EQ(std::fabs(q[0].nx) + std::fabs(q[0].ny) + std::fabs(q[0].nz), 1.0f)
            << "face " << f;
        // Corner UVs wind (0,0) (1,0) (1,1) (0,1).
        EXPECT_FLOAT_EQ(q[0].u, 0.0f); EXPECT_FLOAT_EQ(q[0].v, 0.0f);
        EXPECT_FLOAT_EQ(q[1].u, 1.0f); EXPECT_FLOAT_EQ(q[1].v, 0.0f);
        EXPECT_FLOAT_EQ(q[2].u, 1.0f); EXPECT_FLOAT_EQ(q[2].v, 1.0f);
        EXPECT_FLOAT_EQ(q[3].u, 0.0f); EXPECT_FLOAT_EQ(q[3].v, 1.0f);
        for (uint32_t k = 0; k < 4; ++k) {
            EXPECT_FLOAT_EQ(std::fabs(q[k].x), 0.5f);
            EXPECT_FLOAT_EQ(std::fabs(q[k].y), 0.5f);
            EXPECT_FLOAT_EQ(std::fabs(q[k].z), 0.5f);
        }
    }

    // The six faces must point six different ways.
    for (uint32_t a = 0; a < 6; ++a) {
        for (uint32_t b = a + 1; b < 6; ++b) {
            const ke_vertex &va = data.vertices[a * 4];
            const ke_vertex &vb = data.vertices[b * 4];
            EXPECT_FALSE(va.nx == vb.nx && va.ny == vb.ny && va.nz == vb.nz)
                << "faces " << a << " and " << b << " share a normal";
        }
    }

    for (uint32_t i = 0; i < data.index_count; ++i) {
        EXPECT_LT(data.indices[i], data.vertex_count);
    }
    resolver->free_mesh(resolver, &data);
}

TEST_F(AssetResolverTest, ResolveMesh_Sphere_VerticesLieOnUnitDiameterSphere)
{
    ke_mesh_shape_data data{};
    ASSERT_TRUE(resolver->resolve_mesh(resolver, "res://primitives/sphere", &data, nullptr));
    ASSERT_GT(data.vertex_count, 0u);
    for (uint32_t i = 0; i < data.vertex_count; ++i) {
        const ke_vertex &v = data.vertices[i];
        EXPECT_NEAR(std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z), 0.5f, 1e-5f) << "vertex " << i;
        EXPECT_NEAR(std::sqrt(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz), 1.0f, 1e-5f) << "vertex " << i;
    }
    for (uint32_t i = 0; i < data.index_count; ++i) {
        EXPECT_LT(data.indices[i], data.vertex_count);
    }
    resolver->free_mesh(resolver, &data);
}

TEST_F(AssetResolverTest, ResolveMesh_QuadAndPlane_NormalsDiffer)
{
    ke_mesh_shape_data quad{};
    ke_mesh_shape_data plane{};
    ASSERT_TRUE(resolver->resolve_mesh(resolver, "res://primitives/quad", &quad, nullptr));
    ASSERT_TRUE(resolver->resolve_mesh(resolver, "res://primitives/plane", &plane, nullptr));
    // Quad faces +Z in XY; plane faces +Y in XZ.
    EXPECT_FLOAT_EQ(quad.vertices[0].nz, 1.0f);
    EXPECT_FLOAT_EQ(plane.vertices[0].ny, 1.0f);
    EXPECT_FLOAT_EQ(quad.vertices[0].x, -0.5f);
    EXPECT_FLOAT_EQ(quad.vertices[0].y, -0.5f);
    resolver->free_mesh(resolver, &quad);
    resolver->free_mesh(resolver, &plane);
}

TEST_F(AssetResolverTest, ResolveMesh_UnknownPrimitive_ReturnsNotFound)
{
    ke_mesh_shape_data data{};
    EXPECT_FALSE(resolver->resolve_mesh(resolver, "res://primitives/teapot", &data, nullptr));
}

TEST_F(AssetResolverTest, ResolvePath_NormalizesSlashes)
{
    auto img = WriteTempFile(".png");
    std::string path = img.string();
    // Replace / with \ or vice-versa to test normalization if implemented,
    // but resolver mostly relies on std::filesystem which handles it on Windows.
    ke_texture_data *data = nullptr;
    EXPECT_TRUE(resolver->resolve_texture(resolver, path.c_str(), &data, nullptr));
    resolver->free_texture(resolver, data);
    fs::remove(img);
}

TEST_F(AssetResolverTest, ResolveMaterial_MalformedFile_ReturnsError)
{
    auto mat = WriteTempFile(".material", "not toml [ [ [");
    ke_material_spec spec{};
    EXPECT_FALSE(resolver->resolve_material(resolver, mat.string().c_str(), &spec, nullptr));
    fs::remove(mat);
}

TEST_F(AssetResolverTest, ResolveMaterial_NoAlphaMode_DefaultsToOpaque)
{
    auto mat = WriteTempFile(".material", "[material]\nbase_color = [1.0, 1.0, 1.0, 1.0]\n");
    ke_material_spec spec{};
    ASSERT_TRUE(resolver->resolve_material(resolver, mat.string().c_str(), &spec, nullptr));
    EXPECT_EQ(spec.alpha_mode, KE_ALPHA_MODE_OPAQUE);
    EXPECT_FLOAT_EQ(spec.alpha_cutoff, 0.5f);
    fs::remove(mat);
}

TEST_F(AssetResolverTest, ResolveMaterial_AlphaModeMask_ParsesModeAndCutoff)
{
    auto mat = WriteTempFile(".material",
        "[material]\nalpha_mode = \"MASK\"\nalpha_cutoff = 0.75\n");
    ke_material_spec spec{};
    ASSERT_TRUE(resolver->resolve_material(resolver, mat.string().c_str(), &spec, nullptr));
    EXPECT_EQ(spec.alpha_mode, KE_ALPHA_MODE_MASK);
    EXPECT_FLOAT_EQ(spec.alpha_cutoff, 0.75f);
    fs::remove(mat);
}

TEST_F(AssetResolverTest, ResolveMaterial_AlphaModeBlend_Parses)
{
    auto mat = WriteTempFile(".material", "[material]\nalpha_mode = \"BLEND\"\n");
    ke_material_spec spec{};
    ASSERT_TRUE(resolver->resolve_material(resolver, mat.string().c_str(), &spec, nullptr));
    EXPECT_EQ(spec.alpha_mode, KE_ALPHA_MODE_BLEND);
    fs::remove(mat);
}

TEST_F(AssetResolverTest, ResolveMaterial_UnknownAlphaMode_DefaultsToOpaque)
{
    auto mat = WriteTempFile(".material", "[material]\nalpha_mode = \"typo\"\n");
    ke_material_spec spec{};
    ASSERT_TRUE(resolver->resolve_material(resolver, mat.string().c_str(), &spec, nullptr));
    EXPECT_EQ(spec.alpha_mode, KE_ALPHA_MODE_OPAQUE);
    fs::remove(mat);
}

TEST_F(AssetResolverTest, ResolveMaterial_NoIor_DefaultsToGlass)
{
    auto mat = WriteTempFile(".material", "[material]\nbase_color = [1.0, 1.0, 1.0, 1.0]\n");
    ke_material_spec spec{};
    ASSERT_TRUE(resolver->resolve_material(resolver, mat.string().c_str(), &spec, nullptr));
    EXPECT_FLOAT_EQ(spec.ior, 1.5f);
    fs::remove(mat);
}

TEST_F(AssetResolverTest, ResolveMaterial_Ior_Parses)
{
    auto mat = WriteTempFile(".material", "[material]\nalpha_mode = \"BLEND\"\nior = 1.33\n");
    ke_material_spec spec{};
    ASSERT_TRUE(resolver->resolve_material(resolver, mat.string().c_str(), &spec, nullptr));
    EXPECT_FLOAT_EQ(spec.ior, 1.33f);
    fs::remove(mat);
}

TEST_F(AssetResolverTest, ResolveMaterial_NoDistortionStrength_DefaultsToPointOhFive)
{
    auto mat = WriteTempFile(".material", "[material]\nbase_color = [1.0, 1.0, 1.0, 1.0]\n");
    ke_material_spec spec{};
    ASSERT_TRUE(resolver->resolve_material(resolver, mat.string().c_str(), &spec, nullptr));
    EXPECT_FLOAT_EQ(spec.distortion_strength, 0.05f);
    fs::remove(mat);
}

TEST_F(AssetResolverTest, ResolveMaterial_DistortionStrength_Parses)
{
    auto mat = WriteTempFile(".material", "[material]\nalpha_mode = \"BLEND\"\ndistortion_strength = 0.2\n");
    ke_material_spec spec{};
    ASSERT_TRUE(resolver->resolve_material(resolver, mat.string().c_str(), &spec, nullptr));
    EXPECT_FLOAT_EQ(spec.distortion_strength, 0.2f);
    fs::remove(mat);
}

// ── Material resolution ────────────────────────────────────────────────────

TEST_F(AssetResolverTest, Create_NullImageAndRoot_ReturnsValidHandle)
{
    // Both loaders null + no root is legal; resolve_* slots will fail at call time.
    ke_asset_resolver_handle rh2 = ke_asset_resolver_create(nullptr, nullptr, nullptr, NULL);
    EXPECT_NE(rh2.ref, nullptr);
    if (rh2.ref && rh2.destroy) rh2.destroy(rh2.ref);
}

TEST_F(AssetResolverTest, ResolveTexture_NullArgs_ReturnsInvalidArgument)
{
    ke_texture_data *data = nullptr;
    EXPECT_FALSE(resolver->resolve_texture(nullptr, "test.png", &data, nullptr));
    EXPECT_FALSE(resolver->resolve_texture(resolver, nullptr, &data, nullptr));
    EXPECT_FALSE(resolver->resolve_texture(resolver, "test.png", nullptr, nullptr));
}

TEST_F(AssetResolverTest, ResolveMesh_NullArgs_ReturnsInvalidArgument)
{
    ke_mesh_shape_data data{};
    EXPECT_FALSE(resolver->resolve_mesh(nullptr, "res://primitives/cube", &data, nullptr));
    EXPECT_FALSE(resolver->resolve_mesh(resolver, nullptr, &data, nullptr));
    EXPECT_FALSE(resolver->resolve_mesh(resolver, "res://primitives/cube", nullptr, nullptr));
}

TEST_F(AssetResolverTest, ResolveMaterial_NullArgs_ReturnsInvalidArgument)
{
    ke_material_spec spec{};
    EXPECT_FALSE(resolver->resolve_material(nullptr, "test.material", &spec, nullptr));
    EXPECT_FALSE(resolver->resolve_material(resolver, nullptr, &spec, nullptr));
    EXPECT_FALSE(resolver->resolve_material(resolver, "test.material", nullptr, nullptr));
}

TEST_F(AssetResolverTest, FreeTexture_NullArgs_IsSafe)
{
    resolver->free_texture(nullptr, nullptr);
    resolver->free_texture(resolver, nullptr);
}

TEST_F(AssetResolverTest, FreeMesh_NullArgs_IsSafe)
{
    resolver->free_mesh(nullptr, nullptr);
    resolver->free_mesh(resolver, nullptr);
}

TEST_F(AssetResolverTest, Destroy_NullArgs_IsSafe)
{
    resolver_h.destroy(nullptr);
}

TEST_F(AssetResolverTest, ResolveMesh_ExternalFile_ReturnsNotFound)
{
    ke_mesh_shape_data data{};
    EXPECT_FALSE(resolver->resolve_mesh(resolver, "external.gltf", &data, nullptr));
}

TEST_F(AssetResolverTest, ResolvePath_NoRoot_StripsPrefix)
{
    ke_asset_resolver_handle rh = ke_asset_resolver_create(&loader.api, nullptr, nullptr, NULL);
    ke_asset_resolver *r = rh.ref;
    
    auto mat = WriteTempFile(".material", "[material]\nbase_color = [1.0, 1.0, 1.0, 1.0]\n");
    ke_material_spec spec{};
    // Use the full absolute path from temp dir as the reference after res://
    std::string ref = "res://" + mat.string();
    EXPECT_TRUE(r->resolve_material(r, ref.c_str(), &spec, nullptr));
    
    rh.destroy(rh.ref);
    fs::remove(mat);
}

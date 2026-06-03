#include <gtest/gtest.h>
#include <kernel_engine/framework/node_type_registry.h>
#include <kernel_engine/framework/scene_loader.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/world/variant.h>
#include <kernel_engine/kernel/world/world.h>

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

// ── Test helpers ─────────────────────────────────────────────────────────────

static fs::path WriteTempSceneFile(const std::string &contents)
{
    auto path = fs::temp_directory_path() /
                (std::string("ke_scene_loader_test_") + std::to_string(::rand()) + ".scene.toml");
    std::ofstream(path) << contents;
    return path;
}

// Captures create/set_property calls so the tests can assert what the loader
// drove through the registered type.
struct RecordedNode
{
    ke_entity   entity;
    std::string name;
};

struct RecordedProperty
{
    ke_entity   entity;
    std::string key;
    ke_variant  value;
    std::string string_copy; // ke_variant.s is only valid during the callback, so we copy
};

struct Recorder
{
    std::vector<RecordedNode>     creates;
    std::vector<RecordedProperty> sets;
};

static ke_result RecordCreate(void *ctx, ke_entity e, const char *name)
{
    auto *r = static_cast<Recorder *>(ctx);
    r->creates.push_back({ e, name ? std::string(name) : std::string() });
    return KE_OK;
}

static ke_result RecordSetProperty(void *ctx, ke_entity e, const char *key, ke_variant v)
{
    auto *r = static_cast<Recorder *>(ctx);
    RecordedProperty rec;
    rec.entity = e;
    rec.key    = key ? std::string(key) : std::string();
    rec.value  = v;
    if (v.type == KE_VARIANT_STRING && v.s) {
        rec.string_copy = v.s;
        rec.value.s     = nullptr; // mark: use string_copy
    }
    r->sets.push_back(std::move(rec));
    return KE_OK;
}

// ── Fixture ──────────────────────────────────────────────────────────────────

class SceneLoaderTest : public ::testing::Test
{
protected:
    ke_allocator          *allocator = nullptr;
    ke_world              *world     = nullptr;
    ke_scene_tree         *tree      = nullptr;
    ke_node_type_registry *registry  = nullptr;
    ke_scene_loader       *loader    = nullptr;
    Recorder               recorder;

    void SetUp() override
    {
        allocator = ke_allocator_malloc_create();
        ASSERT_NE(allocator, nullptr);
        ke_world_params params{ allocator };
        ASSERT_EQ(ke_world_create(&params, &world), KE_OK);
        ASSERT_EQ(ke_scene_tree_create(world, allocator, &tree), KE_OK);
        ASSERT_EQ(ke_node_type_registry_create(allocator, &registry), KE_OK);
        ASSERT_EQ(ke_scene_loader_create(allocator, world, tree, registry, &loader), KE_OK);

        // Register a single test type that records every create + set_property.
        ke_node_type t{};
        t.name         = "TestNode";
        t.ctx          = &recorder;
        t.create       = RecordCreate;
        t.set_property = RecordSetProperty;
        ASSERT_EQ(registry->register_type(registry, &t), KE_OK);
    }

    void TearDown() override
    {
        if (loader)   loader->destroy(loader);
        if (registry) registry->destroy(registry);
        if (tree)     tree->destroy(tree);
        if (world)    world->destroy(world);
    }
};

// ── Loader smoke ─────────────────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Load_MissingFile_ReturnsNotFound)
{
    EXPECT_EQ(loader->load(loader, "C:/this/path/does/not/exist.scene.toml"),
              KE_ERROR_NOT_FOUND);
}

TEST_F(SceneLoaderTest, Load_EmptyScene_Succeeds)
{
    auto path = WriteTempSceneFile("");
    EXPECT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    EXPECT_TRUE(recorder.creates.empty());
    fs::remove(path);
}

// ── Node instantiation ──────────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Load_CreatesNodeUnderRoot)
{
    auto path = WriteTempSceneFile(R"(
[[node]]
name = "Player"
type = "TestNode"
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    ASSERT_EQ(recorder.creates.size(), 1u);
    EXPECT_EQ(recorder.creates[0].name, "Player");

    // Tree must see it by name.
    ke_entity found = tree->find_node(tree, "Player");
    EXPECT_EQ(found, recorder.creates[0].entity);
    fs::remove(path);
}

TEST_F(SceneLoaderTest, Load_AttachesChildUnderNamedParent)
{
    auto path = WriteTempSceneFile(R"(
[[node]]
name = "World"
type = "TestNode"

[[node]]
name   = "Player"
type   = "TestNode"
parent = "World"
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    EXPECT_EQ(tree->find_node(tree, "/World/Player"), recorder.creates[1].entity);
    fs::remove(path);
}

TEST_F(SceneLoaderTest, Load_UnknownParent_ReturnsNotFound)
{
    auto path = WriteTempSceneFile(R"(
[[node]]
name   = "Orphan"
type   = "TestNode"
parent = "Missing"
)");
    EXPECT_EQ(loader->load(loader, path.string().c_str()), KE_ERROR_NOT_FOUND);
    fs::remove(path);
}

TEST_F(SceneLoaderTest, Load_UnknownType_ReturnsNotFound)
{
    auto path = WriteTempSceneFile(R"(
[[node]]
name = "Player"
type = "UnregisteredType"
)");
    EXPECT_EQ(loader->load(loader, path.string().c_str()), KE_ERROR_NOT_FOUND);
    fs::remove(path);
}

// ── Transform handling ──────────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Load_AppliesPositionScaleAndRotationQuaternion)
{
    auto path = WriteTempSceneFile(R"(
[[node]]
name = "Player"
type = "TestNode"
[node.transform]
position = [1.0, 2.0, 3.0]
scale    = [4.0, 5.0, 6.0]
rotation = [0.0, 1.0, 0.0, 0.0]
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    auto entity = recorder.creates[0].entity;

    auto tcid = world->transform_id(world);
    auto *t = static_cast<ke_transform_component *>(
        ke_ecs_component_get(world->get_registry(world), entity, tcid));
    ASSERT_NE(t, nullptr);
    EXPECT_FLOAT_EQ(t->position.x, 1.0f);
    EXPECT_FLOAT_EQ(t->position.y, 2.0f);
    EXPECT_FLOAT_EQ(t->position.z, 3.0f);
    EXPECT_FLOAT_EQ(t->scale.x, 4.0f);
    EXPECT_FLOAT_EQ(t->scale.y, 5.0f);
    EXPECT_FLOAT_EQ(t->scale.z, 6.0f);
    EXPECT_FLOAT_EQ(t->rotation.y, 1.0f);
    EXPECT_FLOAT_EQ(t->rotation.w, 0.0f);
    fs::remove(path);
}

TEST_F(SceneLoaderTest, Load_EulerRotation_ConvertedToQuaternion)
{
    auto path = WriteTempSceneFile(R"(
[[node]]
name = "Player"
type = "TestNode"
[node.transform]
rotation_euler = [0.0, 90.0, 0.0]
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    auto entity = recorder.creates[0].entity;
    auto *t = static_cast<ke_transform_component *>(
        ke_ecs_component_get(world->get_registry(world), entity, world->transform_id(world)));
    ASSERT_NE(t, nullptr);
    // 90° yaw → (0, sin(45°), 0, cos(45°)) ≈ (0, 0.7071, 0, 0.7071)
    EXPECT_NEAR(t->rotation.x, 0.0f, 1e-5);
    EXPECT_NEAR(t->rotation.y, 0.70710678f, 1e-5);
    EXPECT_NEAR(t->rotation.z, 0.0f, 1e-5);
    EXPECT_NEAR(t->rotation.w, 0.70710678f, 1e-5);
    fs::remove(path);
}

// ── Properties ──────────────────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Load_ForwardsScalarPropertiesAsVariants)
{
    auto path = WriteTempSceneFile(R"(
[[node]]
name = "Player"
type = "TestNode"
[node.properties]
hp        = 100
speed     = 5.5
alive     = true
asset_path = "res://mesh.obj"
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    ASSERT_EQ(recorder.sets.size(), 4u);

    // Property iteration order isn't guaranteed by tomlplusplus.
    auto find = [&](const std::string &k) -> const RecordedProperty * {
        for (const auto &p : recorder.sets) if (p.key == k) return &p;
        return nullptr;
    };

    auto *hp = find("hp");          ASSERT_NE(hp, nullptr);
    auto *sp = find("speed");       ASSERT_NE(sp, nullptr);
    auto *al = find("alive");       ASSERT_NE(al, nullptr);
    auto *ap = find("asset_path");  ASSERT_NE(ap, nullptr);

    EXPECT_EQ(hp->value.type, KE_VARIANT_INT);
    EXPECT_EQ(hp->value.i, 100);
    EXPECT_EQ(sp->value.type, KE_VARIANT_FLOAT);
    EXPECT_FLOAT_EQ(static_cast<float>(sp->value.f), 5.5f);
    EXPECT_EQ(al->value.type, KE_VARIANT_BOOL);
    EXPECT_TRUE(al->value.b);
    EXPECT_EQ(ap->value.type, KE_VARIANT_STRING);
    EXPECT_EQ(ap->string_copy, "res://mesh.obj");

    fs::remove(path);
}

TEST_F(SceneLoaderTest, Load_VectorPropertiesGetCorrectVariantType)
{
    auto path = WriteTempSceneFile(R"(
[[node]]
name = "Player"
type = "TestNode"
[node.properties]
v2 = [1.0, 2.0]
v3 = [1.0, 2.0, 3.0]
v4 = [1.0, 2.0, 3.0, 4.0]
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    auto find = [&](const std::string &k) -> const RecordedProperty * {
        for (const auto &p : recorder.sets) if (p.key == k) return &p;
        return nullptr;
    };
    EXPECT_EQ(find("v2")->value.type, KE_VARIANT_VEC2);
    EXPECT_EQ(find("v3")->value.type, KE_VARIANT_VEC3);
    EXPECT_EQ(find("v4")->value.type, KE_VARIANT_VEC4);
    fs::remove(path);
}

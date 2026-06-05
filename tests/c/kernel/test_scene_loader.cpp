#include <gtest/gtest.h>
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

// ── Fixture (entity-format only; legacy [[node]] path was removed) ──────────

namespace {
struct DemoComp {
    float    fov;
    float    near_plane;
    uint8_t  ortho;
    ke_vec3  color;
};
}

class SceneLoaderTest : public ::testing::Test
{
protected:
    ke_allocator    *allocator = nullptr;
    ke_world        *world     = nullptr;
    ke_scene_tree   *tree      = nullptr;
    ke_scene_loader *loader    = nullptr;
    ke_component_id  demo_cid  = KE_COMPONENT_INVALID;

    void SetUp() override
    {
        allocator = ke_allocator_malloc_create();
        ASSERT_NE(allocator, nullptr);
        ke_world_params params{ allocator };
        ASSERT_EQ(ke_world_create(&params, &world), KE_OK);
        ASSERT_EQ(ke_scene_tree_create(world, allocator, &tree), KE_OK);
        ASSERT_EQ(ke_scene_loader_create(allocator, world, tree, nullptr, &loader), KE_OK);

        auto *reg = world->get_registry(world);
        static const ke_component_field kFields[] = {
            {"fov",   KE_VARIANT_FLOAT, (uint32_t)offsetof(DemoComp, fov)},
            {"near",  KE_VARIANT_FLOAT, (uint32_t)offsetof(DemoComp, near_plane)},
            {"ortho", KE_VARIANT_BOOL,  (uint32_t)offsetof(DemoComp, ortho)},
            {"color", KE_VARIANT_VEC3,  (uint32_t)offsetof(DemoComp, color)},
        };
        demo_cid = ke_ecs_component_register_v2(
            reg, "demo", sizeof(DemoComp), kFields,
            sizeof(kFields) / sizeof(kFields[0]));
        ASSERT_NE(demo_cid, KE_COMPONENT_INVALID);
    }

    void TearDown() override
    {
        if (loader) loader->destroy(loader);
        if (tree)   tree->destroy(tree);
        if (world)  world->destroy(world);
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
    fs::remove(path);
}

TEST_F(SceneLoaderTest, EntityFormat_AttachesComponent_WritesFields)
{
    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "Cam"
[entity.transform]
position = [1, 2, 3]
[entity.components.demo]
fov = 1.5
near = 0.1
ortho = true
color = [0.8, 0.3, 0.2]
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);

    auto *reg  = world->get_registry(world);
    auto  tcid = world->transform_id(world);
    ke_entity e = tree->find_node(tree, "Cam");
    ASSERT_NE(e, KE_ENTITY_INVALID);

    auto *t = static_cast<ke_transform_component *>(ke_ecs_component_get(reg, e, tcid));
    ASSERT_NE(t, nullptr);
    EXPECT_FLOAT_EQ(t->position.x, 1.0f);
    EXPECT_FLOAT_EQ(t->position.y, 2.0f);
    EXPECT_FLOAT_EQ(t->position.z, 3.0f);

    auto *d = static_cast<DemoComp *>(ke_ecs_component_get(reg, e, demo_cid));
    ASSERT_NE(d, nullptr);
    EXPECT_FLOAT_EQ(d->fov, 1.5f);
    EXPECT_FLOAT_EQ(d->near_plane, 0.1f);
    EXPECT_EQ(d->ortho, 1);
    EXPECT_FLOAT_EQ(d->color.x, 0.8f);
    EXPECT_FLOAT_EQ(d->color.y, 0.3f);
    EXPECT_FLOAT_EQ(d->color.z, 0.2f);
    fs::remove(path);
}

TEST_F(SceneLoaderTest, EntityFormat_ParentReference_ResolvesByName)
{
    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "Parent"

[[entity]]
name = "Child"
parent = "Parent"
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);

    ke_entity parent = tree->find_node(tree, "Parent");
    ke_entity child  = tree->find_node(tree, "Child");
    ASSERT_NE(parent, KE_ENTITY_INVALID);
    ASSERT_NE(child,  KE_ENTITY_INVALID);

    auto *reg  = world->get_registry(world);
    auto  hcid = world->hierarchy_id(world);
    auto *h = static_cast<ke_hierarchy_component *>(ke_ecs_component_get(reg, child, hcid));
    ASSERT_NE(h, nullptr);
    EXPECT_EQ(h->parent, parent);
    fs::remove(path);
}

TEST_F(SceneLoaderTest, EntityFormat_UnknownComponentName_SkippedQuietly)
{
    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "E"
[entity.components.demo]
fov = 1.0
[entity.components.nonexistent]
anything = 42
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);

    auto *reg = world->get_registry(world);
    ke_entity e = tree->find_node(tree, "E");
    auto *d = static_cast<DemoComp *>(ke_ecs_component_get(reg, e, demo_cid));
    ASSERT_NE(d, nullptr);
    EXPECT_FLOAT_EQ(d->fov, 1.0f);
    fs::remove(path);
}

// ── Mesh-shaped component (string buffer + vec4) ───────────────────────────

namespace {
struct MeshLikeComp {
    uint32_t mesh_idx;
    uint32_t material_idx;
    char     primitive[32];
    float    color[4];
};
}

TEST_F(SceneLoaderTest, EntityFormat_MeshLikeComponent_PrimitiveAndColorWritten)
{
    auto *reg = world->get_registry(world);
    static const ke_component_field kMeshFields[] = {
        {"primitive", KE_VARIANT_STRING, (uint32_t)offsetof(MeshLikeComp, primitive), 32},
        {"color",     KE_VARIANT_VEC4,   (uint32_t)offsetof(MeshLikeComp, color),      0},
    };
    ke_component_id mesh_cid = ke_ecs_component_register_v2(
        reg, "mesh_like", sizeof(MeshLikeComp),
        kMeshFields, sizeof(kMeshFields) / sizeof(kMeshFields[0]));
    ASSERT_NE(mesh_cid, KE_COMPONENT_INVALID);

    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "Cube"
[entity.components.mesh_like]
primitive = "cube"
color = [0.8, 0.3, 0.2, 1.0]
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);

    ke_entity e = tree->find_node(tree, "Cube");
    ASSERT_NE(e, KE_ENTITY_INVALID);
    auto *m = static_cast<MeshLikeComp *>(ke_ecs_component_get(reg, e, mesh_cid));
    ASSERT_NE(m, nullptr);
    EXPECT_STREQ(m->primitive, "cube");
    EXPECT_FLOAT_EQ(m->color[0], 0.8f);
    EXPECT_FLOAT_EQ(m->color[1], 0.3f);
    EXPECT_FLOAT_EQ(m->color[2], 0.2f);
    EXPECT_FLOAT_EQ(m->color[3], 1.0f);
    fs::remove(path);
}

// ── [entity.script] dispatches to a language factory ────────────────────────

namespace {
struct ScriptCall { ke_entity entity; std::string type_name; };
struct ScriptCtx  { std::vector<ScriptCall> calls; };

ke_result RecordScriptFactory(void *ctx, ke_entity e, const char *type_name)
{
    auto *c = static_cast<ScriptCtx *>(ctx);
    c->calls.push_back({ e, type_name ? std::string(type_name) : std::string() });
    return KE_OK;
}
}

TEST_F(SceneLoaderTest, EntityFormat_ScriptBlock_InvokesRegisteredFactory)
{
    ScriptCtx cs_ctx, lua_ctx;
    ASSERT_EQ(loader->register_script_language(loader, "csharp", RecordScriptFactory, &cs_ctx),  KE_OK);
    ASSERT_EQ(loader->register_script_language(loader, "lua",    RecordScriptFactory, &lua_ctx), KE_OK);

    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "Paddle"
[entity.script]
language = "csharp"
type     = "Pong.Paddle"

[[entity]]
name = "Bot"
[entity.script]
language = "lua"
type     = "ai/bot"
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);

    ASSERT_EQ(cs_ctx.calls.size(),  1u);
    ASSERT_EQ(lua_ctx.calls.size(), 1u);
    EXPECT_EQ(cs_ctx.calls[0].type_name,  "Pong.Paddle");
    EXPECT_EQ(lua_ctx.calls[0].type_name, "ai/bot");
    EXPECT_NE(cs_ctx.calls[0].entity, KE_ENTITY_INVALID);
    fs::remove(path);
}

TEST_F(SceneLoaderTest, EntityFormat_ScriptBlock_UnknownLanguage_SkippedQuietly)
{
    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "Ghost"
[entity.script]
language = "rust"
type     = "Foo"
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    EXPECT_NE(tree->find_node(tree, "Ghost"), KE_ENTITY_INVALID);
    fs::remove(path);
}

// ── [entity.properties] → scene_properties component ────────────────────────

TEST_F(SceneLoaderTest, EntityFormat_PropertiesBlock_AttachesSceneProperties)
{
    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "HitSound"
[entity.script]
language = "csharp"
type     = "AudioPlayer"
[entity.properties]
Path     = "assets/sounds/hit.wav"
Volume   = 0.5
AutoPlay = true
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);

    auto *reg = world->get_registry(world);
    ke_component_meta meta{};
    ASSERT_EQ(ke_ecs_component_lookup(reg, KE_SCENE_PROPERTIES_COMPONENT_NAME, &meta), KE_OK);

    ke_entity e = tree->find_node(tree, "HitSound");
    ASSERT_NE(e, KE_ENTITY_INVALID);
    auto *bag = static_cast<ke_scene_properties *>(
        ke_ecs_component_get(reg, e, meta.cid));
    ASSERT_NE(bag, nullptr);
    ASSERT_EQ(bag->count, 3u);

    bool sawPath = false, sawVolume = false, sawAuto = false;
    for (uint32_t i = 0; i < bag->count; ++i) {
        const auto &kv = bag->entries[i];
        std::string k(kv.key);
        if (k == "Path") {
            sawPath = true;
            EXPECT_EQ(kv.value.type, KE_VARIANT_STRING);
            EXPECT_STREQ(kv.value.s, "assets/sounds/hit.wav");
        } else if (k == "Volume") {
            sawVolume = true;
            EXPECT_EQ(kv.value.type, KE_VARIANT_FLOAT);
            EXPECT_FLOAT_EQ((float)kv.value.f, 0.5f);
        } else if (k == "AutoPlay") {
            sawAuto = true;
            EXPECT_EQ(kv.value.type, KE_VARIANT_BOOL);
            EXPECT_TRUE(kv.value.b);
        }
    }
    EXPECT_TRUE(sawPath && sawVolume && sawAuto);
    fs::remove(path);
}

TEST_F(SceneLoaderTest, EntityFormat_NoPropertiesBlock_NoSceneProperties)
{
    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "Plain"
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);

    auto *reg = world->get_registry(world);
    ke_component_meta meta{};
    ASSERT_EQ(ke_ecs_component_lookup(reg, KE_SCENE_PROPERTIES_COMPONENT_NAME, &meta), KE_OK);

    ke_entity e = tree->find_node(tree, "Plain");
    EXPECT_EQ(ke_ecs_component_get(reg, e, meta.cid), nullptr);
    fs::remove(path);
}

TEST_F(SceneLoaderTest, EntityFormat_ScriptBlock_ReRegisterReplaces)
{
    ScriptCtx first_ctx, second_ctx;
    ASSERT_EQ(loader->register_script_language(loader, "csharp", RecordScriptFactory, &first_ctx),  KE_OK);
    ASSERT_EQ(loader->register_script_language(loader, "csharp", RecordScriptFactory, &second_ctx), KE_OK);

    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "E"
[entity.script]
language = "csharp"
type     = "T"
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    EXPECT_TRUE(first_ctx.calls.empty());
    EXPECT_EQ(second_ctx.calls.size(), 1u);
    fs::remove(path);
}

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

static ke_result RecordSetProperty(void *ctx, ke_entity e, const char *key, const ke_variant *v)
{
    auto *r = static_cast<Recorder *>(ctx);
    RecordedProperty rec;
    rec.entity = e;
    rec.key    = key ? std::string(key) : std::string();
    rec.value  = *v;
    if (v->type == KE_VARIANT_STRING && v->s) {
        rec.string_copy = v->s;
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
        ASSERT_EQ(ke_scene_loader_create(allocator, world, tree, registry, nullptr, &loader), KE_OK);

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

// ── Nested scenes ───────────────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Load_NestedScene_BySiblingPath_InstantiatesChild)
{
    auto child_path = WriteTempSceneFile(R"(
[[node]]
name = "Inner"
type = "TestNode"
[node.transform]
position = [10.0, 0.0, 0.0]
)");
    // Outer references child by its bare filename — same directory.
    auto child_name = child_path.filename().string();
    auto outer = std::string("[[node]]\nname = \"OuterRoot\"\nscene = \"") + child_name + "\"\n";
    auto outer_path = WriteTempSceneFile(outer);

    ASSERT_EQ(loader->load(loader, outer_path.string().c_str()), KE_OK);
    EXPECT_EQ(recorder.creates.size(), 1u);
    // Inner-root takes the outer entry's name (PackedScene semantics).
    EXPECT_EQ(recorder.creates[0].name, "OuterRoot");
    fs::remove(outer_path);
    fs::remove(child_path);
}

TEST_F(SceneLoaderTest, Load_NestedScene_OuterEntryOverridesTransform)
{
    auto child_path = WriteTempSceneFile(R"(
[[node]]
name = "Inner"
type = "TestNode"
[node.transform]
position = [1.0, 0.0, 0.0]
)");
    auto child_name = child_path.filename().string();
    auto outer = std::string(R"(
[[node]]
name = "Root"
scene = ")") + child_name + R"("
[node.transform]
position = [99.0, 0.0, 0.0]
)";
    auto outer_path = WriteTempSceneFile(outer);

    ASSERT_EQ(loader->load(loader, outer_path.string().c_str()), KE_OK);
    auto entity = recorder.creates[0].entity;
    auto *t = static_cast<ke_transform_component *>(
        ke_ecs_component_get(world->get_registry(world), entity, world->transform_id(world)));
    ASSERT_NE(t, nullptr);
    EXPECT_FLOAT_EQ(t->position.x, 99.0f); // outer wins
    fs::remove(outer_path);
    fs::remove(child_path);
}

// ── Phase 2 of ECS-pure nodes: [[entity]] component-driven path ─────────────
//
// The loader detects the new format by the top-level array name (`entity` vs
// `node`) and writes into components by field name, with zero per-binding
// dispatch code. These tests register a synthetic component with field
// descriptors, load a scene that uses [entity.components.<name>] tables, and
// assert the values landed at the right offsets.

namespace {
struct DemoComp {
    float    fov;
    float    near_plane;
    uint8_t  ortho;
    ke_vec3  color;
};
}

class SceneLoaderEntityFormatTest : public SceneLoaderTest
{
protected:
    ke_component_id demo_cid = KE_COMPONENT_INVALID;

    void SetUp() override
    {
        SceneLoaderTest::SetUp();
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
};

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_AttachesComponent_WritesFields)
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

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_ParentReference_ResolvesByName)
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

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_UnknownComponentName_SkippedQuietly)
{
    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "E"
[entity.components.demo]
fov = 1.0
[entity.components.nonexistent]
anything = 42
)");
    // Unknown components are warnings (not yet logged), not failures.
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);

    auto *reg = world->get_registry(world);
    ke_entity e = tree->find_node(tree, "E");
    auto *d = static_cast<DemoComp *>(ke_ecs_component_get(reg, e, demo_cid));
    ASSERT_NE(d, nullptr);
    EXPECT_FLOAT_EQ(d->fov, 1.0f);
    fs::remove(path);
}

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_DoesNotInvokeLegacyNodeTypeCallbacks)
{
    // A pure [[entity]] file must never reach the node-type registry; old
    // bindings can leave create/set_property pointers wired without effect.
    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "Solo"
[entity.components.demo]
fov = 2.0
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    EXPECT_TRUE(recorder.creates.empty());
    EXPECT_TRUE(recorder.sets.empty());
    fs::remove(path);
}

TEST_F(SceneLoaderEntityFormatTest, LegacyFormat_StillWorks_UnchangedFromBefore)
{
    // Regression: the legacy [[node]] type=... path still dispatches through
    // the node-type registry alongside the new component-driven code path.
    auto path = WriteTempSceneFile(R"(
[[node]]
name = "Player"
type = "TestNode"
)");
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    ASSERT_EQ(recorder.creates.size(), 1u);
    EXPECT_EQ(recorder.creates[0].name, "Player");
    fs::remove(path);
}

// ── Phase 3 integration: mesh-component-shaped fields ───────────────────────
//
// Validates that the new SceneLoader path handles a component with the same
// shape as ke_mesh_component (string-buffer primitive + vec4 color), which is
// what Phase 3 actually ships. The asset system itself (bake + create_mesh)
// needs a live renderer and is exercised by the Lua pong demo, not here.

namespace {
struct MeshLikeComp {
    uint32_t mesh_idx;
    uint32_t material_idx;
    char     primitive[32];
    float    color[4];
};
}

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_MeshLikeComponent_PrimitiveAndColorWritten)
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
    EXPECT_STREQ(m->primitive, "cube"); // verifies the string-buffer copy path
    EXPECT_FLOAT_EQ(m->color[0], 0.8f);
    EXPECT_FLOAT_EQ(m->color[1], 0.3f);
    EXPECT_FLOAT_EQ(m->color[2], 0.2f);
    EXPECT_FLOAT_EQ(m->color[3], 1.0f);
    fs::remove(path);
}

// ── Phase 5.1: [entity.script] dispatches to a language factory ─────────────

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

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_ScriptBlock_InvokesRegisteredFactory)
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

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_ScriptBlock_UnknownLanguage_SkippedQuietly)
{
    auto path = WriteTempSceneFile(R"(
[[entity]]
name = "Ghost"
[entity.script]
language = "rust"
type     = "Foo"
)");
    // No factory registered for "rust" — load still succeeds, entity exists,
    // script attachment is silently skipped.
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    EXPECT_NE(tree->find_node(tree, "Ghost"), KE_ENTITY_INVALID);
    fs::remove(path);
}

// ── Phase 5.2: [entity.properties] → scene_properties component ─────────────

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_PropertiesBlock_AttachesSceneProperties)
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

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_NoPropertiesBlock_NoSceneProperties)
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

TEST_F(SceneLoaderEntityFormatTest, EntityFormat_ScriptBlock_ReRegisterReplaces)
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

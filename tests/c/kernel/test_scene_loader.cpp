#include <gtest/gtest.h>
#include <kernel_engine/framework/scene_loader.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/framework/components.h>
#include <kernel_engine/framework/world.h>
#include <kernel_engine/ecs/variant.h>
#include <kernel_engine/framework/scene_loader_create.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/framework/world_create.h>
#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

namespace fs = std::filesystem;

static fs::path WriteTempScene(const std::string &contents) {
    auto path = fs::temp_directory_path() /
                (std::string("ke_scene_loader_") + std::to_string(std::rand()) + ".scene.toml");
    std::ofstream(path) << contents;
    return path;
}

class SceneLoaderTest : public ::testing::Test
{
protected:
    ke_scheduler_handle scheduler_h{};
    ke_ecs_handle            ecs_h{};
    ke_runtime_handle        runtime_h{};
    ke_scene_tree_handle     tree_h{};
    ke_world_handle          world_h{};
    ke_scene_loader_handle   loader_h{};
    ke_scheduler *scheduler = nullptr;
    ke_ecs            *ecs            = nullptr;
    ke_runtime        *runtime        = nullptr;
    ke_scene_tree     *tree           = nullptr;
    ke_world          *world          = nullptr;
    ke_scene_loader   *loader         = nullptr;

    void SetUp() override
    {
        scheduler_h = ke_scheduler_enki_create(NULL);
        ASSERT_NE(scheduler_h.ref, nullptr);
        scheduler = scheduler_h.ref;

        ke_ecs_flecs_params ep{};
        ecs_h = ke_ecs_flecs_create(&ep, NULL);
        ASSERT_NE(ecs_h.ref, nullptr);
        ecs = ecs_h.ref;
        ke_runtime_params rp{};
        runtime_h = ke_runtime_create(ecs, scheduler, &rp, NULL);
        ASSERT_NE(runtime_h.ref, nullptr);
        runtime = runtime_h.ref;
        tree_h = ke_scene_tree_create(ecs, NULL);
        ASSERT_NE(tree_h.ref, nullptr);
        tree = tree_h.ref;

        ke_world_params wp{};
        wp.scheduler = scheduler;
        wp.ecs = ecs;
        wp.runtime = runtime;
        wp.scene_tree = tree;
        world_h = ke_world_create(&wp, NULL);
        ASSERT_NE(world_h.ref, nullptr);
        world = world_h.ref;

        loader_h = ke_scene_loader_create(world, nullptr, NULL);
        ASSERT_NE(loader_h.ref, nullptr);
        loader = loader_h.ref;
    }

    void TearDown() override
    {
        if (loader_h.ref) loader_h.destroy(loader_h.ref);
        if (world_h.ref) world_h.destroy(world_h.ref);
        // world borrows ecs/runtime/scene_tree — caller destroys in reverse-create order.
        if (tree_h.ref) tree_h.destroy(tree_h.ref);
        if (runtime_h.ref) runtime_h.destroy(runtime_h.ref);
        if (ecs_h.ref) ecs_h.destroy(ecs_h.ref);
        if (scheduler_h.ref) scheduler_h.destroy(scheduler_h.ref);
    }
};

// ── Smoke ────────────────────────────────────────────────────────────────────

TEST_F(SceneLoaderTest, EmptyFile_NoEntities_ReturnsOk)
{
    auto p = WriteTempScene("[scene]\nname = \"empty\"\n");
    EXPECT_TRUE(loader->load(loader, p.string().c_str(), NULL));
}

TEST_F(SceneLoaderTest, MissingFile_ReturnsNotFound)
{
    EXPECT_FALSE(loader->load(loader, "no_such_file_anywhere.scene.toml", NULL));
}

TEST_F(SceneLoaderTest, BasicEntity_AppearsInTree)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Player"
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    EXPECT_NE(tree->find_node(tree, "Player", NULL), KE_ENTITY_INVALID);
}

TEST_F(SceneLoaderTest, ParentReferencesPriorEntity)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "World"

[[entity]]
name = "Child"
parent = "World"
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    EXPECT_NE(tree->find_node(tree, "World/Child", NULL), KE_ENTITY_INVALID);
}

// ── Transform application ──────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Transform_PositionApplied)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "X"
[entity.transform]
position = [1.0, 2.0, 3.0]
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "X", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "transform", &meta, nullptr));
    auto *t = (ke_transform_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(t, nullptr);
    EXPECT_FLOAT_EQ(t->position.x, 1.0f);
    EXPECT_FLOAT_EQ(t->position.y, 2.0f);
    EXPECT_FLOAT_EQ(t->position.z, 3.0f);
}

// ── [entity.components.X] via apply registry ──────────────────────────────

TEST_F(SceneLoaderTest, MeshComponent_AppliedByName)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Crate"
[entity.components.mesh]
primitive = "cube"
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Crate", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "mesh", &meta, nullptr));
    auto *m = (ke_mesh_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(m, nullptr);
    EXPECT_STREQ(m->primitive, "cube");
}

TEST_F(SceneLoaderTest, CameraComponent_FovDegreesAlias)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Cam"
[entity.components.camera]
fov_degrees = 60.0
near_plane = 0.1
far_plane = 100.0
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Cam", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "camera", &meta, nullptr));
    auto *c = (ke_camera_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(c, nullptr);
    // 60° → 1.0472 rad
    EXPECT_NEAR(c->fov, 1.0472f, 0.001f);
    EXPECT_FLOAT_EQ(c->near_plane, 0.1f);
    EXPECT_FLOAT_EQ(c->far_plane, 100.0f);
}

// ── scene_properties bag ───────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Properties_AttachedAsSceneProperties)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "P"
[entity.properties]
Health = 100
MoveAction = "PlayerMove"
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "P", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, KE_SCENE_PROPERTIES_COMPONENT_NAME, &meta, nullptr));
    auto *bag = (ke_scene_properties *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(bag, nullptr);
    EXPECT_EQ(bag->count, 2u);

    bool saw_health = false, saw_move = false;
    for (uint32_t i = 0; i < bag->count; ++i) {
        if (strcmp(bag->entries[i].key, "Health") == 0) {
            EXPECT_EQ(bag->entries[i].value.type, KE_VARIANT_INT);
            EXPECT_EQ(bag->entries[i].value.i, 100);
            saw_health = true;
        }
        if (strcmp(bag->entries[i].key, "MoveAction") == 0) {
            EXPECT_EQ(bag->entries[i].value.type, KE_VARIANT_STRING);
            EXPECT_STREQ(bag->entries[i].value.s, "PlayerMove");
            saw_move = true;
        }
    }
    EXPECT_TRUE(saw_health);
    EXPECT_TRUE(saw_move);
}

// ── Script factory dispatch ────────────────────────────────────────────────

namespace {
struct ScriptCallSpy {
    int   calls = 0;
    char  last_type[64] = {0};
    ke_entity last_entity = KE_ENTITY_INVALID;
};

bool spy_factory(void *ctx, ke_entity entity, const char *type_name, ke_error **out_error) {
    (void)out_error;
    auto *s = static_cast<ScriptCallSpy *>(ctx);
    s->calls++;
    s->last_entity = entity;
    std::strncpy(s->last_type, type_name, sizeof(s->last_type) - 1);
    return true;
}
}

TEST_F(SceneLoaderTest, Script_FactoryReceivesEntityAndType)
{
    ScriptCallSpy spy;
    ASSERT_TRUE(loader->register_script_factory(loader, spy_factory, &spy, nullptr));

    auto p = WriteTempScene(R"(
[[entity]]
name = "Paddle"
type = "PaddleController"
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));

    EXPECT_EQ(spy.calls, 1);
    EXPECT_STREQ(spy.last_type, "PaddleController");
    EXPECT_EQ(spy.last_entity, tree->find_node(tree, "Paddle", NULL));
}

TEST_F(SceneLoaderTest, Script_NoFactory_EntityStillCreated)
{
    // No factory registered — entity is created but script dispatch is a no-op.
    auto p = WriteTempScene(R"(
[[entity]]
name = "Lone"
type = "Whatever"
)");
    EXPECT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    EXPECT_NE(tree->find_node(tree, "Lone", NULL), KE_ENTITY_INVALID);
}

// ── User component with custom apply ────────────────────────────────────

namespace {
struct DemoComp {
    float   fov;
    int32_t mode;
};

void demo_apply(void *c, const ke_variant_table_entry *entries, uint32_t count) {
    DemoComp *d = (DemoComp *)c;
    for (uint32_t i = 0; i < count; ++i) {
        if (strcmp(entries[i].key, "fov") == 0) {
            if (entries[i].value.type == KE_VARIANT_FLOAT) d->fov = (float)entries[i].value.f;
            else if (entries[i].value.type == KE_VARIANT_INT) d->fov = (float)entries[i].value.i;
        } else if (strcmp(entries[i].key, "mode") == 0 && entries[i].value.type == KE_VARIANT_INT) {
            d->mode = (int32_t)entries[i].value.i;
        }
    }
}
}

TEST_F(SceneLoaderTest, UserComponent_AppliedThroughCustomCallback)
{
    ke_component_id demo_cid = ecs->component_register(ecs, "demo", sizeof(DemoComp));
    ASSERT_NE(demo_cid, KE_COMPONENT_INVALID);
    ASSERT_TRUE(world->register_component_apply(world, demo_cid, demo_apply, nullptr));

    auto p = WriteTempScene(R"(
[[entity]]
name = "Test"
[entity.components.demo]
fov = 1.5
mode = 7
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));

    ke_entity e = tree->find_node(tree, "Test", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);
    auto *d = (DemoComp *)ecs->component_get(ecs, e, demo_cid);
    ASSERT_NE(d, nullptr);
    EXPECT_FLOAT_EQ(d->fov, 1.5f);
    EXPECT_EQ(d->mode, 7);
}

// ── Create-arg validation ──────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Create_RejectsNullArgs)
{
    EXPECT_EQ(ke_scene_loader_create(nullptr, nullptr, NULL).ref, nullptr);
}

TEST_F(SceneLoaderTest, Destroy_NullSelf_IsSafe)
{
    loader_h.destroy(nullptr);  // must not crash
}

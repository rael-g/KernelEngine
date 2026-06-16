#include <gtest/gtest.h>
#include <kernel_engine/framework/scene_loader.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/framework/components.h>
#include <kernel_engine/framework/world.h>
#include <kernel_engine/ecs/variant.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/framework/scene_loader_create.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/framework/world_create.h>
#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/task_scheduler/enki/enki_task_scheduler.h>

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
    ke_allocator      *allocator      = nullptr;
    ke_task_scheduler *task_scheduler = nullptr;
    ke_ecs            *ecs            = nullptr;
    ke_runtime        *runtime        = nullptr;
    ke_scene_tree     *tree           = nullptr;
    ke_world          *world          = nullptr;
    ke_scene_loader   *loader         = nullptr;

    void SetUp() override
    {
        allocator = ke_allocator_malloc_create();
        ASSERT_EQ(ke_task_scheduler_enki_create(allocator, &task_scheduler), KE_OK);

        ke_ecs_flecs_params ep{};
        ASSERT_EQ(ke_ecs_flecs_create(&ep, &ecs), KE_OK);
        ke_runtime_params rp{};
        ASSERT_EQ(ke_runtime_create(ecs, task_scheduler, &rp, &runtime), KE_OK);
        ASSERT_EQ(ke_scene_tree_create(ecs, &tree), KE_OK);

        ke_world_params wp{};
        wp.task_scheduler = task_scheduler;
        wp.ecs = ecs;
        wp.runtime = runtime;
        wp.scene_tree = tree;
        ASSERT_EQ(ke_world_create(&wp, &world), KE_OK);

        ASSERT_EQ(ke_scene_loader_create(world, nullptr, &loader), KE_OK);
    }

    void TearDown() override
    {
        if (loader) loader->destroy(loader);
        if (world) world->destroy(world);
        // world borrows ecs/runtime/scene_tree — caller destroys in reverse-create order.
        if (tree) tree->destroy(tree);
        if (runtime) runtime->destroy(runtime);
        if (ecs) ecs->destroy(ecs);
        if (task_scheduler) task_scheduler->destroy(task_scheduler);
    }
};

// ── Smoke ────────────────────────────────────────────────────────────────────

TEST_F(SceneLoaderTest, EmptyFile_NoEntities_ReturnsOk)
{
    auto p = WriteTempScene("[scene]\nname = \"empty\"\n");
    EXPECT_EQ(loader->load(loader, p.string().c_str()), KE_OK);
}

TEST_F(SceneLoaderTest, MissingFile_ReturnsNotFound)
{
    EXPECT_EQ(loader->load(loader, "no_such_file_anywhere.scene.toml"), KE_ERROR_NOT_FOUND);
}

TEST_F(SceneLoaderTest, BasicEntity_AppearsInTree)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Player"
)");
    ASSERT_EQ(loader->load(loader, p.string().c_str()), KE_OK);
    EXPECT_NE(tree->find_node(tree, "Player"), KE_ENTITY_INVALID);
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
    ASSERT_EQ(loader->load(loader, p.string().c_str()), KE_OK);
    EXPECT_NE(tree->find_node(tree, "World/Child"), KE_ENTITY_INVALID);
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
    ASSERT_EQ(loader->load(loader, p.string().c_str()), KE_OK);
    ke_entity e = tree->find_node(tree, "X");
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_EQ(ecs->component_lookup(ecs, "transform", &meta), KE_OK);
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
color = [0.8, 0.3, 0.2, 1.0]
)");
    ASSERT_EQ(loader->load(loader, p.string().c_str()), KE_OK);
    ke_entity e = tree->find_node(tree, "Crate");
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_EQ(ecs->component_lookup(ecs, "mesh", &meta), KE_OK);
    auto *m = (ke_mesh_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(m, nullptr);
    EXPECT_STREQ(m->primitive, "cube");
    EXPECT_FLOAT_EQ(m->color[0], 0.8f);
    EXPECT_FLOAT_EQ(m->color[3], 1.0f);
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
    ASSERT_EQ(loader->load(loader, p.string().c_str()), KE_OK);
    ke_entity e = tree->find_node(tree, "Cam");
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_EQ(ecs->component_lookup(ecs, "camera", &meta), KE_OK);
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
    ASSERT_EQ(loader->load(loader, p.string().c_str()), KE_OK);
    ke_entity e = tree->find_node(tree, "P");
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_EQ(ecs->component_lookup(ecs, KE_SCENE_PROPERTIES_COMPONENT_NAME, &meta), KE_OK);
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

ke_result spy_factory(void *ctx, ke_entity entity, const char *type_name) {
    auto *s = static_cast<ScriptCallSpy *>(ctx);
    s->calls++;
    s->last_entity = entity;
    std::strncpy(s->last_type, type_name, sizeof(s->last_type) - 1);
    return KE_OK;
}
}

TEST_F(SceneLoaderTest, Script_FactoryReceivesEntityAndType)
{
    ScriptCallSpy spy;
    ASSERT_EQ(loader->register_script_factory(loader, spy_factory, &spy), KE_OK);

    auto p = WriteTempScene(R"(
[[entity]]
name = "Paddle"
type = "PaddleController"
)");
    ASSERT_EQ(loader->load(loader, p.string().c_str()), KE_OK);

    EXPECT_EQ(spy.calls, 1);
    EXPECT_STREQ(spy.last_type, "PaddleController");
    EXPECT_EQ(spy.last_entity, tree->find_node(tree, "Paddle"));
}

TEST_F(SceneLoaderTest, Script_NoFactory_EntityStillCreated)
{
    // No factory registered — entity is created but script dispatch is a no-op.
    auto p = WriteTempScene(R"(
[[entity]]
name = "Lone"
type = "Whatever"
)");
    EXPECT_EQ(loader->load(loader, p.string().c_str()), KE_OK);
    EXPECT_NE(tree->find_node(tree, "Lone"), KE_ENTITY_INVALID);
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
    ASSERT_EQ(world->register_component_apply(world, demo_cid, demo_apply), KE_OK);

    auto p = WriteTempScene(R"(
[[entity]]
name = "Test"
[entity.components.demo]
fov = 1.5
mode = 7
)");
    ASSERT_EQ(loader->load(loader, p.string().c_str()), KE_OK);

    ke_entity e = tree->find_node(tree, "Test");
    ASSERT_NE(e, KE_ENTITY_INVALID);
    auto *d = (DemoComp *)ecs->component_get(ecs, e, demo_cid);
    ASSERT_NE(d, nullptr);
    EXPECT_FLOAT_EQ(d->fov, 1.5f);
    EXPECT_EQ(d->mode, 7);
}

// ── Create-arg validation ──────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Create_RejectsNullArgs)
{
    ke_scene_loader *l = nullptr;
    EXPECT_EQ(ke_scene_loader_create(nullptr, nullptr, &l), KE_ERROR_INVALID_ARGUMENT);
    EXPECT_EQ(ke_scene_loader_create(world, nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(SceneLoaderTest, Destroy_NullSelf_IsSafe)
{
    loader->destroy(nullptr);  // must not crash
}

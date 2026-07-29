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

// ── subscene composition ───────────────────────────────────────────────────

TEST_F(SceneLoaderTest, Subscene_EntitiesAreSplicedUnderTheReferencingName)
{
    // Mirrors the shape real scenes use: an outer entity names a subscene file,
    // and the subscene's own entities back-reference each other by name.
    auto sub = WriteTempScene(R"(
[[entity]]
name = "Root"

[[entity]]
name   = "Visual"
parent = "Root"
[entity.transform]
scale = [0.3, 1.8, 1.0]
)");

    auto main = WriteTempScene(std::string(R"(
[[entity]]
name = "Holder"

[[entity]]
name  = "PaddleLeft"
scene = ")") + sub.generic_string() + R"("
[entity.transform]
position = [-7.5, 0.0, 0.0]
)");

    ASSERT_TRUE(loader->load(loader, main.string().c_str(), NULL));

    // The subscene root takes the referencing entity's name, not its own.
    ke_entity paddle = tree->find_node(tree, "PaddleLeft", NULL);
    ASSERT_NE(paddle, KE_ENTITY_INVALID);

    // And the subscene's child came along with it.
    ke_entity visual = tree->find_node(tree, "Visual", NULL);
    ASSERT_NE(visual, KE_ENTITY_INVALID);

    ke_component_meta hmeta;
    ASSERT_TRUE(ecs->component_lookup(ecs, KE_COMPONENT_NAME_HIERARCHY, &hmeta, nullptr));
    auto *vh = (ke_hierarchy_component *)ecs->component_get(ecs, visual, hmeta.cid);
    ASSERT_NE(vh, nullptr);
    EXPECT_EQ(vh->parent, paddle) << "subscene child must hang off the spliced root";

    // The outer [transform] override must reach the subscene root.
    ke_component_meta tmeta;
    ASSERT_TRUE(ecs->component_lookup(ecs, KE_COMPONENT_NAME_TRANSFORM, &tmeta, nullptr));
    auto *pt = (ke_transform_component *)ecs->component_get(ecs, paddle, tmeta.cid);
    ASSERT_NE(pt, nullptr);
    EXPECT_FLOAT_EQ(pt->position.x, -7.5f);

    // The subscene's own transform survived too.
    auto *vt = (ke_transform_component *)ecs->component_get(ecs, visual, tmeta.cid);
    ASSERT_NE(vt, nullptr);
    EXPECT_FLOAT_EQ(vt->scale.x, 0.3f);
    EXPECT_FLOAT_EQ(vt->scale.y, 1.8f);
}

TEST_F(SceneLoaderTest, Subscene_OuterTransformAndComponentOverridesStayPairedPerInstance)
{
    // Pong's exact shape: two entities reference the SAME subscene, and each
    // carries BOTH an outer [transform] override (applied early) and an outer
    // [components.X] override (applied late). The two overrides for one instance
    // must land on the same spliced root — a mix-up swaps e.g. paddle position
    // and control action across the two instances.
    auto sub = WriteTempScene(R"(
[[entity]]
name = "Root"
)");

    std::string main_text =
        "[[entity]]\nname = \"Holder\"\n\n"
        "[[entity]]\nname = \"Left\"\nscene = \"" + sub.generic_string() + "\"\n"
        "[entity.transform]\nposition = [-7.5, 0.0, 0.0]\n"
        "[entity.components.camera]\nfar_plane = 111.0\n\n"
        "[[entity]]\nname = \"Right\"\nscene = \"" + sub.generic_string() + "\"\n"
        "[entity.transform]\nposition = [7.5, 0.0, 0.0]\n"
        "[entity.components.camera]\nfar_plane = 222.0\n";
    auto main = WriteTempScene(main_text);

    ASSERT_TRUE(loader->load(loader, main.string().c_str(), NULL));

    ke_component_meta tmeta, cmeta;
    ASSERT_TRUE(ecs->component_lookup(ecs, KE_COMPONENT_NAME_TRANSFORM, &tmeta, nullptr));
    ASSERT_TRUE(ecs->component_lookup(ecs, KE_COMPONENT_NAME_CAMERA, &cmeta, nullptr));

    ke_entity left = tree->find_node(tree, "Left", NULL);
    ke_entity right = tree->find_node(tree, "Right", NULL);
    ASSERT_NE(left, KE_ENTITY_INVALID);
    ASSERT_NE(right, KE_ENTITY_INVALID);

    auto *lt = (ke_transform_component *)ecs->component_get(ecs, left, tmeta.cid);
    auto *lc = (ke_camera_component *)ecs->component_get(ecs, left, cmeta.cid);
    auto *rt = (ke_transform_component *)ecs->component_get(ecs, right, tmeta.cid);
    auto *rc = (ke_camera_component *)ecs->component_get(ecs, right, cmeta.cid);
    ASSERT_NE(lt, nullptr); ASSERT_NE(lc, nullptr);
    ASSERT_NE(rt, nullptr); ASSERT_NE(rc, nullptr);

    // Position -7.5 must be paired with far_plane 111 (both from the Left block).
    EXPECT_FLOAT_EQ(lt->position.x, -7.5f);
    EXPECT_FLOAT_EQ(lc->far_plane, 111.0f);
    EXPECT_FLOAT_EQ(rt->position.x, 7.5f);
    EXPECT_FLOAT_EQ(rc->far_plane, 222.0f);
}

// ── light applies ──────────────────────────────────────────────────────────

TEST_F(SceneLoaderTest, DirectionalLight_VectorAndScalarFormsAgree)
{
    // The apply accepts both a vec3 ("direction") and per-axis scalars
    // ("dir_x"); both spellings must land in the same fields.
    auto p = WriteTempScene(R"(
[[entity]]
name = "SunVec"
[entity.components.directional_light]
direction = [-0.4, -1.0, -0.3]
color = [1.0, 0.9, 0.8]
ambient = [0.03, 0.03, 0.04]
intensity = 3.0

[[entity]]
name = "SunScalar"
[entity.components.directional_light]
dir_x = -0.4
dir_y = -1.0
dir_z = -0.3
r = 1.0
g = 0.9
b = 0.8
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "directional_light", &meta, nullptr));

    ke_entity ev = tree->find_node(tree, "SunVec", NULL);
    ASSERT_NE(ev, KE_ENTITY_INVALID);
    auto *lv = (ke_directional_light_component *)ecs->component_get(ecs, ev, meta.cid);
    ASSERT_NE(lv, nullptr);
    EXPECT_FLOAT_EQ(lv->dir_x, -0.4f);
    EXPECT_FLOAT_EQ(lv->dir_y, -1.0f);
    EXPECT_FLOAT_EQ(lv->dir_z, -0.3f);
    EXPECT_FLOAT_EQ(lv->r, 1.0f);
    EXPECT_FLOAT_EQ(lv->g, 0.9f);
    EXPECT_FLOAT_EQ(lv->b, 0.8f);
    EXPECT_FLOAT_EQ(lv->ambient_r, 0.03f);
    EXPECT_FLOAT_EQ(lv->ambient_b, 0.04f);
    EXPECT_FLOAT_EQ(lv->intensity, 3.0f);

    ke_entity es = tree->find_node(tree, "SunScalar", NULL);
    ASSERT_NE(es, KE_ENTITY_INVALID);
    auto *ls = (ke_directional_light_component *)ecs->component_get(ecs, es, meta.cid);
    ASSERT_NE(ls, nullptr);
    EXPECT_FLOAT_EQ(ls->dir_x, lv->dir_x);
    EXPECT_FLOAT_EQ(ls->dir_y, lv->dir_y);
    EXPECT_FLOAT_EQ(ls->dir_z, lv->dir_z);
    EXPECT_FLOAT_EQ(ls->r, lv->r);
    EXPECT_FLOAT_EQ(ls->g, lv->g);
    EXPECT_FLOAT_EQ(ls->b, lv->b);
}

TEST_F(SceneLoaderTest, PointLight_FieldsApplied)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Bulb"
[entity.components.point_light]
color = [0.2, 0.4, 0.6]
radius = 12.5
intensity = 2.0
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Bulb", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "point_light", &meta, nullptr));
    auto *l = (ke_point_light_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(l, nullptr);
    EXPECT_FLOAT_EQ(l->r, 0.2f);
    EXPECT_FLOAT_EQ(l->g, 0.4f);
    EXPECT_FLOAT_EQ(l->b, 0.6f);
    EXPECT_FLOAT_EQ(l->radius, 12.5f);
    EXPECT_FLOAT_EQ(l->intensity, 2.0f);
}

TEST_F(SceneLoaderTest, SpotLight_FieldsApplied)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Lamp"
[entity.components.spot_light]
direction = [0.0, -1.0, 0.0]
color = [1.0, 0.5, 0.25]
inner_angle = 0.3
outer_angle = 0.6
range = 20.0
intensity = 4.0
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Lamp", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "spot_light", &meta, nullptr));
    auto *l = (ke_spot_light_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(l, nullptr);
    EXPECT_FLOAT_EQ(l->dir_y, -1.0f);
    EXPECT_FLOAT_EQ(l->r, 1.0f);
    EXPECT_FLOAT_EQ(l->g, 0.5f);
    EXPECT_FLOAT_EQ(l->b, 0.25f);
    EXPECT_FLOAT_EQ(l->inner_angle, 0.3f);
    EXPECT_FLOAT_EQ(l->outer_angle, 0.6f);
    EXPECT_FLOAT_EQ(l->range, 20.0f);
    EXPECT_FLOAT_EQ(l->intensity, 4.0f);
}

TEST_F(SceneLoaderTest, Transform_RotationEulerDegreesToQuaternion)
{
    // 90° about Y alone: the ZYX intrinsic composition must reduce to
    // (0, sin45, 0, cos45) with no bleed into the other axes.
    auto p = WriteTempScene(R"(
[[entity]]
name = "Turned"
[entity.transform]
rotation_euler = [0.0, 90.0, 0.0]
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Turned", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "transform", &meta, nullptr));
    auto *t = (ke_transform_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(t, nullptr);
    EXPECT_NEAR(t->rotation.x, 0.0f, 1e-5f);
    EXPECT_NEAR(t->rotation.y, 0.70710678f, 1e-5f);
    EXPECT_NEAR(t->rotation.z, 0.0f, 1e-5f);
    EXPECT_NEAR(t->rotation.w, 0.70710678f, 1e-5f);
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

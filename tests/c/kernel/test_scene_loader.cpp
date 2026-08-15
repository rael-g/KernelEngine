#include <gtest/gtest.h>
#include <kernel_engine/framework/scene_loader.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/framework/components.h>
#include <kernel_engine/render/components.h>
#include <kernel_engine/render/ui/components.h>
#include <kernel_engine/audio/components.h>
#include <kernel_engine/audio/module/audio_module.h>
#include <kernel_engine/physics/components.h>
#include <kernel_engine/physics/body2d/body2d_module.h>
#include <kernel_engine/framework/world.h>
#include <kernel_engine/ecs/variant.h>
#include <kernel_engine/framework/scene_loader_create.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/framework/world_create.h>
#include <kernel_engine/render/module/render_module_create.h>
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
        tree_h = ke_scene_tree_create(ecs, NULL, NULL);
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

        // Camera/mesh/directional_light/point_light/spot_light are render's own
        // scene-file vocabulary, not framework's — this test exercises the
        // scene loader (framework's job) applying them, so it registers
        // render's apply callbacks itself, exactly as a real host's render
        // module would (ke_render_module_create does this same call).
        ASSERT_TRUE(ke_render_register_scene_apply(ecs, world));
        ASSERT_TRUE(ke_audio_register_scene_apply(ecs, world));
        ASSERT_TRUE(ke_physics_register_scene_apply(ecs, world));

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

TEST_F(SceneLoaderTest, Transform2d_PoseAppliedAndRotationIsDegrees)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Flat"
[entity.transform2d]
position = [1.0, 2.0]
rotation = 90.0
scale    = [3.0, 4.0]
depth    = 5.0
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Flat", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "transform2d", &meta, nullptr));
    auto *t = (ke_transform2d_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(t, nullptr);
    EXPECT_FLOAT_EQ(t->position.x, 1.0f);
    EXPECT_FLOAT_EQ(t->position.y, 2.0f);
    // Authored in degrees like every other rotation in a scene file, stored in
    // radians like the physics that reads it.
    EXPECT_NEAR(t->rotation, 1.57079633f, 1e-5f);
    EXPECT_FLOAT_EQ(t->scale.x, 3.0f);
    EXPECT_FLOAT_EQ(t->scale.y, 4.0f);
    EXPECT_FLOAT_EQ(t->depth, 5.0f);
}

TEST_F(SceneLoaderTest, Sprite2d_FieldsApplied)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Coin"
[entity.sprite2d]
texture    = "res://atlas.png"
region     = [0.25, 0.5, 0.25, 0.5]
size       = [2.0, 3.0]
pivot      = [0.0, 1.0]
flip_h     = true
color      = [0.5, 0.6, 0.7, 0.8]
alpha_mode = "blend"
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Coin", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "sprite2d", &meta, nullptr));
    auto *sp = (ke_sprite2d_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(sp, nullptr);
    EXPECT_STREQ(sp->texture, "res://atlas.png");
    EXPECT_FLOAT_EQ(sp->region.x, 0.25f);
    EXPECT_FLOAT_EQ(sp->region.w, 0.5f);
    EXPECT_FLOAT_EQ(sp->size.x, 2.0f);
    EXPECT_FLOAT_EQ(sp->pivot.y, 1.0f);
    EXPECT_TRUE(sp->flip_h);
    EXPECT_FALSE(sp->flip_v);
    EXPECT_FLOAT_EQ(sp->color.w, 0.8f);
    // Authored by the enumerator's name, which no field table can express.
    EXPECT_EQ(sp->alpha_mode, (uint32_t)KE_ALPHA_MODE_BLEND);
    // Never authorable: the resolve system owns it.
    EXPECT_FALSE(sp->attached);
}

TEST_F(SceneLoaderTest, PartialBlock_LeavesTheHeaderDefaultStanding)
{
    // The bug this covers: a block authoring one field used to zero every other,
    // so a mesh with only a color came out with roughness 0 where the header
    // declares 1 — deterministic, invisible, and wrong.
    auto p = WriteTempScene(R"(
[[entity]]
name = "Partial"
[entity.mesh]
color = [1.0, 0.0, 0.0, 1.0]
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Partial", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "mesh", &meta, nullptr));
    auto *m = (ke_mesh_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(m, nullptr);
    EXPECT_FLOAT_EQ(m->base_color.x, 1.0f);
    EXPECT_FLOAT_EQ(m->roughness, 1.0f);
    EXPECT_FLOAT_EQ(m->ior, 1.5f);
    EXPECT_FLOAT_EQ(m->alpha_cutoff, 0.5f);
}

// ── [entity.X] via apply registry ──────────────────────────────

TEST_F(SceneLoaderTest, MeshComponent_AppliedByName)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Crate"
[entity.mesh]
mesh = "cube"
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
[entity.camera]
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
        "[entity.camera]\nfar_plane = 111.0\n\n"
        "[[entity]]\nname = \"Right\"\nscene = \"" + sub.generic_string() + "\"\n"
        "[entity.transform]\nposition = [7.5, 0.0, 0.0]\n"
        "[entity.camera]\nfar_plane = 222.0\n";
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

TEST_F(SceneLoaderTest, DirectionalLight_FieldsApplied)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "SunVec"
[entity.directional_light]
direction = [-0.4, -1.0, -0.3]
color = [1.0, 0.9, 0.8]
ambient = [0.03, 0.03, 0.04]
intensity = 3.0
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "directional_light", &meta, nullptr));

    ke_entity ev = tree->find_node(tree, "SunVec", NULL);
    ASSERT_NE(ev, KE_ENTITY_INVALID);
    auto *lv = (ke_directional_light_component *)ecs->component_get(ecs, ev, meta.cid);
    ASSERT_NE(lv, nullptr);
    EXPECT_FLOAT_EQ(lv->direction.x, -0.4f);
    EXPECT_FLOAT_EQ(lv->direction.y, -1.0f);
    EXPECT_FLOAT_EQ(lv->direction.z, -0.3f);
    EXPECT_FLOAT_EQ(lv->color.x, 1.0f);
    EXPECT_FLOAT_EQ(lv->color.y, 0.9f);
    EXPECT_FLOAT_EQ(lv->color.z, 0.8f);
    EXPECT_FLOAT_EQ(lv->ambient.x, 0.03f);
    EXPECT_FLOAT_EQ(lv->ambient.z, 0.04f);
    EXPECT_FLOAT_EQ(lv->intensity, 3.0f);
}

TEST_F(SceneLoaderTest, Label_FieldsApplied)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Score"
[entity.label]
text = "0"
anchor = [0.3, 0.0]
offset = [0.0, 60.0]
color = [0.95, 0.95, 0.95, 1.0]
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Score", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "label", &meta, nullptr));
    auto *l = (ke_label_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(l, nullptr);
    EXPECT_STREQ(l->text, "0");
    EXPECT_FLOAT_EQ(l->anchor[0], 0.3f);
    EXPECT_FLOAT_EQ(l->offset[1], 60.0f);
    EXPECT_FLOAT_EQ(l->color[3], 1.0f);
    // glyph_count is the shaping system's output, so a scene must not be able to
    // seed it even though it sits in the same component.
    EXPECT_EQ(l->glyph_count, 0u);
}

TEST_F(SceneLoaderTest, AudioPlayer_FieldsApplied)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Hit"
[entity.audio_player]
path = "assets/sounds/hit.wav"
volume = 0.5
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Hit", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "audio_player", &meta, nullptr));
    auto *a = (ke_audio_player_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(a, nullptr);
    EXPECT_STREQ(a->path, "assets/sounds/hit.wav");
    EXPECT_FLOAT_EQ(a->volume, 0.5f);
}

TEST_F(SceneLoaderTest, LegacyComponentsNesting_IsNotRead)
{
    // The old [entity.components.X] level is gone. Loading anyway would leave the
    // author guessing which fields landed, so the file is refused outright.
    auto p = WriteTempScene(R"(
[[entity]]
name = "Old"
[entity.components.point_light]
radius = 42.0
)");
    ke_error *err = nullptr;
    EXPECT_FALSE(loader->load(loader, p.string().c_str(), &err));
    EXPECT_NE(err, nullptr);
}

TEST_F(SceneLoaderTest, InternalComponent_CannotBeAuthored)
{
    // hierarchy holds entity ids the scene cannot know; writing one would point
    // the graph at an entity that does not exist.
    auto p = WriteTempScene(R"(
[[entity]]
name = "Parent"

[[entity]]
name   = "Child"
parent = "Parent"
[entity.hierarchy]
parent = 999
)");
    ke_error *err = nullptr;
    EXPECT_FALSE(loader->load(loader, p.string().c_str(), &err));
    EXPECT_NE(err, nullptr);
}

TEST_F(SceneLoaderTest, UnknownComponent_FailsTheLoad)
{
    // A typo in a component name is the failure this whole format is exposed to,
    // and the only moment it can be caught is now, synchronously, at load.
    auto p = WriteTempScene(R"(
[[entity]]
name = "Typo"
[entity.point_ligth]
radius = 42.0
)");
    ke_error *err = nullptr;
    EXPECT_FALSE(loader->load(loader, p.string().c_str(), &err));
    EXPECT_NE(err, nullptr);
}

TEST_F(SceneLoaderTest, Collider2D_FieldsApplied)
{
    // The shape a scene gives a collider used to arrive through a C#-only
    // property bag, so a non-C# host loaded the same file and got the default.
    auto p = WriteTempScene(R"(
[[entity]]
name = "Shape"
[entity.collider2d]
half_extents = [0.18, 0.18]
restitution  = 1.0
friction     = 0.0
)");
    ASSERT_TRUE(loader->load(loader, p.string().c_str(), NULL));
    ke_entity e = tree->find_node(tree, "Shape", NULL);
    ASSERT_NE(e, KE_ENTITY_INVALID);

    ke_component_meta meta;
    ASSERT_TRUE(ecs->component_lookup(ecs, "collider2d", &meta, nullptr));
    auto *col = (ke_collider2d_component *)ecs->component_get(ecs, e, meta.cid);
    ASSERT_NE(col, nullptr);
    EXPECT_FLOAT_EQ(col->half_extents.x, 0.18f);
    EXPECT_FLOAT_EQ(col->half_extents.y, 0.18f);
    EXPECT_FLOAT_EQ(col->restitution, 1.0f);
    EXPECT_FLOAT_EQ(col->friction, 0.0f);
}

TEST_F(SceneLoaderTest, PointLight_FieldsApplied)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Bulb"
[entity.point_light]
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
    EXPECT_FLOAT_EQ(l->color.x, 0.2f);
    EXPECT_FLOAT_EQ(l->color.y, 0.4f);
    EXPECT_FLOAT_EQ(l->color.z, 0.6f);
    EXPECT_FLOAT_EQ(l->radius, 12.5f);
    EXPECT_FLOAT_EQ(l->intensity, 2.0f);
}

TEST_F(SceneLoaderTest, SpotLight_FieldsApplied)
{
    auto p = WriteTempScene(R"(
[[entity]]
name = "Lamp"
[entity.spot_light]
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
    EXPECT_FLOAT_EQ(l->direction.y, -1.0f);
    EXPECT_FLOAT_EQ(l->color.x, 1.0f);
    EXPECT_FLOAT_EQ(l->color.y, 0.5f);
    EXPECT_FLOAT_EQ(l->color.z, 0.25f);
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
    ke_component_id demo_cid = ecs->component_register(ecs, "demo", sizeof(DemoComp), nullptr);
    ASSERT_NE(demo_cid, KE_COMPONENT_INVALID);
    ASSERT_TRUE(world->register_component_apply(world, demo_cid, demo_apply, nullptr));

    auto p = WriteTempScene(R"(
[[entity]]
name = "Test"
[entity.demo]
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

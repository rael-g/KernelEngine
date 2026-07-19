#include <gtest/gtest.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/framework/components.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>

class SceneTreeTest : public ::testing::Test
{
protected:
    ke_ecs_handle        ecs_h{};
    ke_scene_tree_handle tree_h{};
    ke_ecs        *ecs       = nullptr;
    ke_scene_tree *tree      = nullptr;

    void SetUp() override
    {
        ke_ecs_flecs_params ep{};
        ecs_h = ke_ecs_flecs_create(&ep, NULL);
        ASSERT_NE(ecs_h.ref, nullptr);
        ecs = ecs_h.ref;
        tree_h = ke_scene_tree_create(ecs, NULL);
        ASSERT_NE(tree_h.ref, nullptr);
        tree = tree_h.ref;
    }
    void TearDown() override
    {
        if (tree_h.ref && tree_h.destroy) tree_h.destroy(tree_h.ref);
        if (ecs_h.ref && ecs_h.destroy)   ecs_h.destroy(ecs_h.ref);
    }
};

// ── Root + creation ─────────────────────────────────────────────────────────

TEST_F(SceneTreeTest, Root_IsValid)
{
    ke_entity r = tree->root(tree);
    EXPECT_NE(r, KE_ENTITY_INVALID);
    EXPECT_EQ(tree->root(tree), r);
}

TEST_F(SceneTreeTest, CreateNode_AttachesToRootWhenParentInvalid)
{
    ke_entity child = tree->create_node(tree, "X", KE_ENTITY_INVALID, NULL, NULL);
    EXPECT_NE(child, KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "X", NULL), child);
}

TEST_F(SceneTreeTest, CreateNode_AcceptsExplicitParent)
{
    ke_entity parent = tree->create_node(tree, "Parent", KE_ENTITY_INVALID, NULL, NULL);
    ke_entity child  = tree->create_node(tree, "Child",  parent, NULL, NULL);
    EXPECT_NE(child, KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "Parent/Child", NULL), child);
}

// ── find_node ───────────────────────────────────────────────────────────────

TEST_F(SceneTreeTest, FindNode_EmptyOrNullReturnsInvalid)
{
    EXPECT_EQ(tree->find_node(tree, "", NULL), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, nullptr, NULL), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, FindNode_MissReturnsInvalid)
{
    EXPECT_EQ(tree->find_node(tree, "Unknown", NULL), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "/Unknown", NULL), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, FindNode_ByName_FindsDirectChild)
{
    ke_entity child = tree->create_node(tree, "Player", KE_ENTITY_INVALID, NULL, NULL);
    EXPECT_EQ(tree->find_node(tree, "Player", NULL), child);
}

TEST_F(SceneTreeTest, FindNode_ByName_FindsNestedFirstMatch)
{
    ke_entity inter  = tree->create_node(tree, "Intermediate", KE_ENTITY_INVALID, NULL, NULL);
    ke_entity target = tree->create_node(tree, "Target",       inter, NULL, NULL);
    EXPECT_EQ(tree->find_node(tree, "Target", NULL), target);
}

TEST_F(SceneTreeTest, FindNode_ByPath_NavigatesSegments)
{
    ke_entity world  = tree->create_node(tree, "World",  KE_ENTITY_INVALID, NULL, NULL);
    ke_entity player = tree->create_node(tree, "Player", world, NULL, NULL);
    EXPECT_EQ(tree->find_node(tree, "/World/Player",  NULL), player);
    EXPECT_EQ(tree->find_node(tree, "World/Player",   NULL), player);
    EXPECT_EQ(tree->find_node(tree, "./World/Player", NULL), player);
}

TEST_F(SceneTreeTest, FindNode_ByPath_NonexistentSegmentReturnsInvalid)
{
    tree->create_node(tree, "World", KE_ENTITY_INVALID, NULL, NULL);
    EXPECT_EQ(tree->find_node(tree, "/World/Missing", NULL), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, FindNode_ByPath_HandlesLeadingDot)
{
    ke_entity world_node = tree->create_node(tree, "World", KE_ENTITY_INVALID, NULL, NULL);
    EXPECT_EQ(tree->find_node(tree, "./World", NULL), world_node);
}

TEST_F(SceneTreeTest, FindNode_ByPath_TrailingSlash_Works)
{
    ke_entity world_node = tree->create_node(tree, "World", KE_ENTITY_INVALID, NULL, NULL);
    EXPECT_EQ(tree->find_node(tree, "/World/", NULL), world_node);
}

TEST_F(SceneTreeTest, FindNode_ByPath_DeepRelative_Works)
{
    ke_entity a = tree->create_node(tree, "A", KE_ENTITY_INVALID, NULL, NULL);
    ke_entity b = tree->create_node(tree, "B", a, NULL, NULL);
    ke_entity c = tree->create_node(tree, "C", b, NULL, NULL);
    EXPECT_EQ(tree->find_node(tree, "A/B/C", NULL), c);
}

TEST_F(SceneTreeTest, FindNode_ByPath_EmptySegments_AreSkipped)
{
    ke_entity a = tree->create_node(tree, "A", KE_ENTITY_INVALID, NULL, NULL);
    EXPECT_EQ(tree->find_node(tree, "//A///", NULL), a);
}

// ── destroy_node ────────────────────────────────────────────────────────────

TEST_F(SceneTreeTest, DestroyNode_RejectsInvalidEntity)
{
    EXPECT_FALSE(tree->destroy_node(tree, KE_ENTITY_INVALID, NULL, NULL));
}

TEST_F(SceneTreeTest, DestroyNode_DestroysSubtree)
{
    ke_entity world_node = tree->create_node(tree, "World",  KE_ENTITY_INVALID, NULL, NULL);
    tree->create_node(tree, "Player", world_node, NULL, NULL);
    tree->create_node(tree, "Enemy",  world_node, NULL, NULL);

    EXPECT_TRUE(tree->destroy_node(tree, world_node, NULL, NULL));
    EXPECT_EQ(tree->find_node(tree, "World",  NULL), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "Player", NULL), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "Enemy",  NULL), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, DestroyNode_UnlinksFromParent)
{
    ke_entity child = tree->create_node(tree, "X", KE_ENTITY_INVALID, NULL, NULL);
    EXPECT_TRUE(tree->destroy_node(tree, child, NULL, NULL));
    EXPECT_EQ(tree->find_node(tree, "X", NULL), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, DestroyNode_UnlinksFromMiddleOfChain)
{
    // Create 3 nodes; create_node prepends, so list is Root -> 3 -> 2 -> 1.
    tree->create_node(tree, "1", KE_ENTITY_INVALID, NULL, NULL);
    ke_entity c2 = tree->create_node(tree, "2", KE_ENTITY_INVALID, NULL, NULL);
    tree->create_node(tree, "3", KE_ENTITY_INVALID, NULL, NULL);

    EXPECT_TRUE(tree->destroy_node(tree, c2, NULL, NULL));

    // 1 and 3 should still resolve.
    EXPECT_NE(tree->find_node(tree, "1", NULL), KE_ENTITY_INVALID);
    EXPECT_NE(tree->find_node(tree, "3", NULL), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "2", NULL), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, DestroyAll_ClearsChildrenButKeepsRoot)
{
    tree->create_node(tree, "A", KE_ENTITY_INVALID, NULL, NULL);
    tree->create_node(tree, "B", KE_ENTITY_INVALID, NULL, NULL);

    tree->destroy_all(tree);

    EXPECT_NE(tree->root(tree), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "A", NULL), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "B", NULL), KE_ENTITY_INVALID);
}

// ── Factory edge cases ──────────────────────────────────────────────────────

// ── Transform propagation ───────────────────────────────────────────────────

namespace {

ke_transform_component *TransformOf(ke_ecs *ecs, ke_entity e)
{
    ke_component_meta meta;
    if (!ecs->component_lookup(ecs, KE_COMPONENT_NAME_TRANSFORM, &meta, nullptr)) return nullptr;
    return (ke_transform_component *)ecs->component_get(ecs, e, meta.cid);
}

} // namespace

TEST_F(SceneTreeTest, PropagateTransforms_FreshNodeIsIdentity)
{
    ke_entity n = tree->create_node(tree, "N", KE_ENTITY_INVALID, NULL, NULL);
    ASSERT_NE(n, KE_ENTITY_INVALID);
    tree->propagate_transforms(tree);

    auto *t = TransformOf(ecs, n);
    ASSERT_NE(t, nullptr);
    for (int i = 0; i < 16; ++i) {
        EXPECT_FLOAT_EQ(t->world_matrix.m[i], (i % 5 == 0) ? 1.0f : 0.0f) << "cell " << i;
    }
}

TEST_F(SceneTreeTest, PropagateTransforms_ChildTranslationComposesWithParent)
{
    ke_entity parent = tree->create_node(tree, "P", KE_ENTITY_INVALID, NULL, NULL);
    ke_entity child  = tree->create_node(tree, "C", parent, NULL, NULL);
    ASSERT_NE(parent, KE_ENTITY_INVALID);
    ASSERT_NE(child, KE_ENTITY_INVALID);

    TransformOf(ecs, parent)->position = ke_vec3{ 10.0f, 0.0f, 0.0f };
    TransformOf(ecs, child)->position  = ke_vec3{  1.0f, 2.0f, 3.0f };
    tree->propagate_transforms(tree);

    // Row-major with translation in the last row.
    auto *pt = TransformOf(ecs, parent);
    EXPECT_FLOAT_EQ(pt->world_matrix.m[12], 10.0f);

    auto *ct = TransformOf(ecs, child);
    EXPECT_FLOAT_EQ(ct->world_matrix.m[12], 11.0f);
    EXPECT_FLOAT_EQ(ct->world_matrix.m[13], 2.0f);
    EXPECT_FLOAT_EQ(ct->world_matrix.m[14], 3.0f);
}

TEST_F(SceneTreeTest, PropagateTransforms_ParentScaleScalesChildOffset)
{
    ke_entity parent = tree->create_node(tree, "P", KE_ENTITY_INVALID, NULL, NULL);
    ke_entity child  = tree->create_node(tree, "C", parent, NULL, NULL);

    TransformOf(ecs, parent)->scale   = ke_vec3{ 2.0f, 2.0f, 2.0f };
    TransformOf(ecs, child)->position = ke_vec3{ 1.0f, 0.0f, 0.0f };
    tree->propagate_transforms(tree);

    // The child sits one unit out in a parent scaled 2x, so it lands at 2.
    auto *ct = TransformOf(ecs, child);
    EXPECT_FLOAT_EQ(ct->world_matrix.m[12], 2.0f);
    // And inherits the scale on its own basis row.
    EXPECT_FLOAT_EQ(ct->world_matrix.m[0], 2.0f);
}

TEST_F(SceneTreeTest, PropagateTransforms_QuarterTurnAboutYMapsXToMinusZ)
{
    ke_entity n = tree->create_node(tree, "N", KE_ENTITY_INVALID, NULL, NULL);
    // 90° about Y as a quaternion.
    const float s = 0.70710678f;
    TransformOf(ecs, n)->rotation = ke_quat{ 0.0f, s, 0.0f, s };
    tree->propagate_transforms(tree);

    // The basis X row must rotate onto -Z.
    auto *t = TransformOf(ecs, n);
    EXPECT_NEAR(t->world_matrix.m[0], 0.0f, 1e-5f);
    EXPECT_NEAR(t->world_matrix.m[1], 0.0f, 1e-5f);
    EXPECT_NEAR(t->world_matrix.m[2], -1.0f, 1e-5f);
}

TEST_F(SceneTreeTest, PropagateTransforms_GrandchildAccumulatesWholeChain)
{
    ke_entity a = tree->create_node(tree, "A", KE_ENTITY_INVALID, NULL, NULL);
    ke_entity b = tree->create_node(tree, "B", a, NULL, NULL);
    ke_entity d = tree->create_node(tree, "D", b, NULL, NULL);

    TransformOf(ecs, a)->position = ke_vec3{ 1.0f, 0.0f, 0.0f };
    TransformOf(ecs, b)->position = ke_vec3{ 0.0f, 2.0f, 0.0f };
    TransformOf(ecs, d)->position = ke_vec3{ 0.0f, 0.0f, 4.0f };
    tree->propagate_transforms(tree);

    auto *dt = TransformOf(ecs, d);
    EXPECT_FLOAT_EQ(dt->world_matrix.m[12], 1.0f);
    EXPECT_FLOAT_EQ(dt->world_matrix.m[13], 2.0f);
    EXPECT_FLOAT_EQ(dt->world_matrix.m[14], 4.0f);
}

TEST_F(SceneTreeTest, Create_NullArgs_ReturnsInvalidArgument)
{
    EXPECT_EQ(ke_scene_tree_create(nullptr, NULL).ref, nullptr);
}

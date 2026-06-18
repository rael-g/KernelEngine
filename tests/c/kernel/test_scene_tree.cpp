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
        ASSERT_EQ(ke_ecs_flecs_create(&ep, &ecs_h, NULL), KE_OK);
        ecs = ecs_h.ref;
        ASSERT_EQ(ke_scene_tree_create(ecs, &tree_h, NULL), KE_OK);
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
    ke_entity child = tree->create_node(tree, "X", KE_ENTITY_INVALID);
    EXPECT_NE(child, KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "X"), child);
}

TEST_F(SceneTreeTest, CreateNode_AcceptsExplicitParent)
{
    ke_entity parent = tree->create_node(tree, "Parent", KE_ENTITY_INVALID);
    ke_entity child  = tree->create_node(tree, "Child",  parent);
    EXPECT_NE(child, KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "Parent/Child"), child);
}

// ── find_node ───────────────────────────────────────────────────────────────

TEST_F(SceneTreeTest, FindNode_EmptyOrNullReturnsInvalid)
{
    EXPECT_EQ(tree->find_node(tree, ""), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, nullptr), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, FindNode_MissReturnsInvalid)
{
    EXPECT_EQ(tree->find_node(tree, "Unknown"), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "/Unknown"), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, FindNode_ByName_FindsDirectChild)
{
    ke_entity child = tree->create_node(tree, "Player", KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "Player"), child);
}

TEST_F(SceneTreeTest, FindNode_ByName_FindsNestedFirstMatch)
{
    ke_entity inter  = tree->create_node(tree, "Intermediate", KE_ENTITY_INVALID);
    ke_entity target = tree->create_node(tree, "Target",       inter);
    EXPECT_EQ(tree->find_node(tree, "Target"), target);
}

TEST_F(SceneTreeTest, FindNode_ByPath_NavigatesSegments)
{
    ke_entity world  = tree->create_node(tree, "World",  KE_ENTITY_INVALID);
    ke_entity player = tree->create_node(tree, "Player", world);
    EXPECT_EQ(tree->find_node(tree, "/World/Player"),  player);
    EXPECT_EQ(tree->find_node(tree, "World/Player"),   player);
    EXPECT_EQ(tree->find_node(tree, "./World/Player"), player);
}

TEST_F(SceneTreeTest, FindNode_ByPath_NonexistentSegmentReturnsInvalid)
{
    tree->create_node(tree, "World", KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "/World/Missing"), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, FindNode_ByPath_HandlesLeadingDot)
{
    ke_entity world_node = tree->create_node(tree, "World", KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "./World"), world_node);
}

TEST_F(SceneTreeTest, FindNode_ByPath_TrailingSlash_Works)
{
    ke_entity world_node = tree->create_node(tree, "World", KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "/World/"), world_node);
}

TEST_F(SceneTreeTest, FindNode_ByPath_DeepRelative_Works)
{
    ke_entity a = tree->create_node(tree, "A", KE_ENTITY_INVALID);
    ke_entity b = tree->create_node(tree, "B", a);
    ke_entity c = tree->create_node(tree, "C", b);
    EXPECT_EQ(tree->find_node(tree, "A/B/C"), c);
}

TEST_F(SceneTreeTest, FindNode_ByPath_EmptySegments_AreSkipped)
{
    ke_entity a = tree->create_node(tree, "A", KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "//A///"), a);
}

// ── destroy_node ────────────────────────────────────────────────────────────

TEST_F(SceneTreeTest, DestroyNode_RejectsInvalidEntity)
{
    EXPECT_EQ(tree->destroy_node(tree, KE_ENTITY_INVALID, NULL), KE_ERROR);
}

TEST_F(SceneTreeTest, DestroyNode_DestroysSubtree)
{
    ke_entity world_node = tree->create_node(tree, "World",  KE_ENTITY_INVALID);
    tree->create_node(tree, "Player", world_node);
    tree->create_node(tree, "Enemy",  world_node);

    EXPECT_EQ(tree->destroy_node(tree, world_node, NULL), KE_OK);
    EXPECT_EQ(tree->find_node(tree, "World"),  KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "Player"), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "Enemy"),  KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, DestroyNode_UnlinksFromParent)
{
    ke_entity child = tree->create_node(tree, "X", KE_ENTITY_INVALID);
    EXPECT_EQ(tree->destroy_node(tree, child, NULL), KE_OK);
    EXPECT_EQ(tree->find_node(tree, "X"), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, DestroyNode_UnlinksFromMiddleOfChain)
{
    // Create 3 nodes; create_node prepends, so list is Root -> 3 -> 2 -> 1.
    tree->create_node(tree, "1", KE_ENTITY_INVALID);
    ke_entity c2 = tree->create_node(tree, "2", KE_ENTITY_INVALID);
    tree->create_node(tree, "3", KE_ENTITY_INVALID);

    EXPECT_EQ(tree->destroy_node(tree, c2, NULL), KE_OK);

    // 1 and 3 should still resolve.
    EXPECT_NE(tree->find_node(tree, "1"), KE_ENTITY_INVALID);
    EXPECT_NE(tree->find_node(tree, "3"), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "2"), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, DestroyAll_ClearsChildrenButKeepsRoot)
{
    tree->create_node(tree, "A", KE_ENTITY_INVALID);
    tree->create_node(tree, "B", KE_ENTITY_INVALID);

    tree->destroy_all(tree);

    EXPECT_NE(tree->root(tree), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "A"), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "B"), KE_ENTITY_INVALID);
}

// ── Factory edge cases ──────────────────────────────────────────────────────

TEST_F(SceneTreeTest, Create_NullArgs_ReturnsInvalidArgument)
{
    ke_scene_tree_handle t{};
    EXPECT_EQ(ke_scene_tree_create(nullptr, &t, NULL), KE_ERROR);
    EXPECT_EQ(ke_scene_tree_create(ecs, nullptr, NULL), KE_ERROR);
}

#include <gtest/gtest.h>
#include <kernel_engine/kernel/framework/scene_tree.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <cstring>

// Helper: attaches a freshly-created entity under `parent` with the given name,
// wiring it into the linked-list child chain so find_node / destroy_node walks
// can find it. Returns the new entity.
static ke_entity AddChild(ke_world *world, ke_entity parent, const char *name,
                          uint32_t hcid, uint32_t ncid)
{
    auto reg = world->get_registry(world);
    ke_entity e = ke_ecs_entity_create(reg);
    auto h  = (ke_hierarchy_component *)ke_ecs_component_add(reg, e, hcid);
    h->parent = parent;
    h->first_child = h->next_sibling = h->prev_sibling = KE_ENTITY_INVALID;

    auto n  = (ke_name_component *)ke_ecs_component_add(reg, e, ncid);
    std::strncpy(n->name, name, sizeof(n->name) - 1);

    // Insert at the front of the parent's child list. Simple and keeps the
    // test setup tidy; FindRecursive doesn't depend on insertion order.
    auto ph = (ke_hierarchy_component *)ke_ecs_component_get(reg, parent, hcid);
    if (ph->first_child != KE_ENTITY_INVALID) {
        auto sib = (ke_hierarchy_component *)ke_ecs_component_get(reg, ph->first_child, hcid);
        sib->prev_sibling = e;
        h->next_sibling = ph->first_child;
    }
    ph->first_child = e;
    return e;
}

class SceneTreeTest : public ::testing::Test
{
protected:
    ke_allocator   *allocator = nullptr;
    ke_world       *world     = nullptr;
    ke_scene_tree  *tree      = nullptr;

    void SetUp() override
    {
        allocator = ke_allocator_malloc_create();
        ASSERT_NE(allocator, nullptr);
        ke_world_params params{ allocator };
        ASSERT_EQ(ke_world_create(&params, &world), KE_OK);
        ASSERT_EQ(ke_scene_tree_create(world, allocator, &tree), KE_OK);
    }
    void TearDown() override
    {
        if (tree && tree->destroy) tree->destroy(tree);
        if (world && world->destroy) world->destroy(world);
    }
};

TEST_F(SceneTreeTest, Root_IsValid)
{
    ke_entity r = tree->root(tree);
    EXPECT_NE(r, KE_ENTITY_INVALID);
    // Calling again returns the same root.
    EXPECT_EQ(tree->root(tree), r);
}

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
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity child = AddChild(world, tree->root(tree), "Player", hcid, ncid);
    EXPECT_EQ(tree->find_node(tree, "Player"), child);
}

TEST_F(SceneTreeTest, FindNode_ByName_FindsNestedFirstMatch)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity inter = AddChild(world, tree->root(tree), "Intermediate", hcid, ncid);
    ke_entity target = AddChild(world, inter, "Target", hcid, ncid);
    EXPECT_EQ(tree->find_node(tree, "Target"), target);
}

TEST_F(SceneTreeTest, FindNode_ByPath_NavigatesSegments)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity world_node = AddChild(world, tree->root(tree), "World", hcid, ncid);
    ke_entity player     = AddChild(world, world_node,       "Player", hcid, ncid);

    EXPECT_EQ(tree->find_node(tree, "/World/Player"), player);
    EXPECT_EQ(tree->find_node(tree, "World/Player"),  player);
    EXPECT_EQ(tree->find_node(tree, "./World/Player"), player);
}

TEST_F(SceneTreeTest, FindNode_ByPath_NonexistentSegmentReturnsInvalid)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    AddChild(world, tree->root(tree), "World", hcid, ncid);
    EXPECT_EQ(tree->find_node(tree, "/World/Missing"), KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, DestroyNode_RejectsInvalidEntity)
{
    EXPECT_EQ(tree->destroy_node(tree, KE_ENTITY_INVALID), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(SceneTreeTest, DestroyNode_DestroysSubtree)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity world_node = AddChild(world, tree->root(tree), "World", hcid, ncid);
    AddChild(world, world_node, "Player", hcid, ncid);
    AddChild(world, world_node, "Enemy",  hcid, ncid);

    EXPECT_EQ(tree->destroy_node(tree, world_node), KE_OK);
    // Descendants gone too.
    EXPECT_EQ(tree->find_node(tree, "World"),  KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "Player"), KE_ENTITY_INVALID);
    EXPECT_EQ(tree->find_node(tree, "Enemy"),  KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, DestroyNode_UnlinksFromParent)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity root = tree->root(tree);
    ke_entity child = AddChild(world, root, "X", hcid, ncid);

    EXPECT_EQ(tree->destroy_node(tree, child), KE_OK);

    // Root's first_child should no longer reference the destroyed entity.
    auto rh = (ke_hierarchy_component *)ke_ecs_component_get(
        world->get_registry(world), root, hcid);
    ASSERT_NE(rh, nullptr);
    EXPECT_EQ(rh->first_child, KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, Create_NullArgs_ReturnsInvalidArgument)
{
    ke_scene_tree *t = nullptr;
    EXPECT_EQ(ke_scene_tree_create(nullptr, allocator, &t), KE_ERROR_INVALID_ARGUMENT);
    EXPECT_EQ(ke_scene_tree_create(world, nullptr, &t), KE_ERROR_INVALID_ARGUMENT);
    EXPECT_EQ(ke_scene_tree_create(world, allocator, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(SceneTreeTest, FindNode_ByPath_HandlesLeadingDot)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity world_node = AddChild(world, tree->root(tree), "World", hcid, ncid);
    EXPECT_EQ(tree->find_node(tree, "./World"), world_node);
}

TEST_F(SceneTreeTest, FindNode_ByPath_TrailingSlash_Works)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity world_node = AddChild(world, tree->root(tree), "World", hcid, ncid);
    EXPECT_EQ(tree->find_node(tree, "/World/"), world_node);
}

TEST_F(SceneTreeTest, DestroyNode_UnlinksFromMiddleOfChain)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity root = tree->root(tree);
    ke_entity c1 = AddChild(world, root, "1", hcid, ncid);
    ke_entity c2 = AddChild(world, root, "2", hcid, ncid);
    ke_entity c3 = AddChild(world, root, "3", hcid, ncid);

    // Chain is Root -> 3 -> 2 -> 1 (AddChild inserts at front)
    EXPECT_EQ(tree->destroy_node(tree, c2), KE_OK);

    // Verify 3's next is now 1
    auto h3 = (ke_hierarchy_component *)ke_ecs_component_get(world->get_registry(world), c3, hcid);
    EXPECT_EQ(h3->next_sibling, c1);
    
    // Verify 1's prev is now 3
    auto h1 = (ke_hierarchy_component *)ke_ecs_component_get(world->get_registry(world), c1, hcid);
    EXPECT_EQ(h1->prev_sibling, c3);
}

TEST_F(SceneTreeTest, DestroyNode_UnlinksFirstChild)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity root = tree->root(tree);
    ke_entity c1 = AddChild(world, root, "1", hcid, ncid);
    ke_entity c2 = AddChild(world, root, "2", hcid, ncid);

    // Chain is Root -> 2 -> 1
    EXPECT_EQ(tree->destroy_node(tree, c2), KE_OK);

    // Verify root's first child is now 1
    auto hroot = (ke_hierarchy_component *)ke_ecs_component_get(world->get_registry(world), root, hcid);
    EXPECT_EQ(hroot->first_child, c1);
    
    // Verify 1's prev is now invalid
    auto h1 = (ke_hierarchy_component *)ke_ecs_component_get(world->get_registry(world), c1, hcid);
    EXPECT_EQ(h1->prev_sibling, KE_ENTITY_INVALID);
}

TEST_F(SceneTreeTest, FindNode_ByPath_DeepRelative_Works)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity a = AddChild(world, tree->root(tree), "A", hcid, ncid);
    ke_entity b = AddChild(world, a, "B", hcid, ncid);
    ke_entity c = AddChild(world, b, "C", hcid, ncid);
    
    EXPECT_EQ(tree->find_node(tree, "A/B/C"), c);
}

TEST_F(SceneTreeTest, FindNode_ByPath_EmptySegments_AreSkipped)
{
    auto hcid = world->hierarchy_id(world);
    auto ncid = world->name_id(world);
    ke_entity a = AddChild(world, tree->root(tree), "A", hcid, ncid);
    
    EXPECT_EQ(tree->find_node(tree, "//A///"), a);
}

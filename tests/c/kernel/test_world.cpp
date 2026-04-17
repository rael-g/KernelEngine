#include <gtest/gtest.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/engine/frame.h>
#include <string.h>
#include <vector>

class WorldTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_world* world = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_world_params params = { alloc, nullptr, nullptr };
        ke_result res = ke_world_create(&params, &world);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (world) world->destroy(world);
        if (alloc) alloc->destroy(alloc);
    }
};

// --- Creation Tests ---

TEST(WorldInitTest, Create_NullArgs_ReturnsInvalidArgument) {
    ke_world* w = nullptr;
    ASSERT_EQ(ke_world_create(nullptr, &w), KE_ERROR_INVALID_ARGUMENT);
}

TEST(WorldInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_world* w = nullptr;
    ke_world_params params = { nullptr, nullptr, nullptr };
    ASSERT_EQ(ke_world_create(&params, &w), KE_ERROR_INVALID_ARGUMENT);
}

static void* fail_alloc(ke_allocator* alloc, size_t size, size_t alignment) { return nullptr; }
static void safe_free(ke_allocator* alloc, void* ptr) { if (ptr) free(ptr); }

TEST(WorldInitTest, Create_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.free = safe_free;
    ke_world* w = nullptr;
    ke_world_params params = { &fa, nullptr, nullptr };
    ASSERT_EQ(ke_world_create(&params, &w), KE_ERROR_OUT_OF_MEMORY);
}

static int alloc_count = 0;
static void* fail_second_alloc(ke_allocator* alloc, size_t size, size_t alignment) {
    if (alloc_count++ == 0) return malloc(size);
    return nullptr;
}

TEST(WorldInitTest, Create_InternalEcsAllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_second_alloc;
    fa.free = safe_free;
    alloc_count = 0;
    ke_world* w = nullptr;
    ke_world_params params = { &fa, nullptr, nullptr };
    ASSERT_EQ(ke_world_create(&params, &w), KE_ERROR_OUT_OF_MEMORY);
}

// --- Hierarchy and Node Lifecycle ---

TEST_F(WorldTest, GetRoot_ReturnsValidEntity) {
    ASSERT_NE(world->get_root(world), KE_ENTITY_INVALID);
}

TEST_F(WorldTest, CreateNode_ReturnsValidEntity) {
    ke_entity e = world->create_node(world, "Node", world->get_root(world));
    ASSERT_NE(e, KE_ENTITY_INVALID);
}

TEST_F(WorldTest, CreateNode_NullName_Works) {
    ke_entity e = world->create_node(world, nullptr, world->get_root(world));
    ASSERT_NE(e, KE_ENTITY_INVALID);
}

TEST_F(WorldTest, DestroyNode_InvalidEntity_ReturnsError) {
    ASSERT_EQ(world->destroy_node(world, KE_ENTITY_INVALID), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(WorldTest, DestroyNode_Root_ReturnsError) {
    ASSERT_EQ(world->destroy_node(world, world->get_root(world)), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(WorldTest, DestroyNode_RemovesFromHierarchy) {
    ke_entity parent = world->get_root(world);
    ke_entity child = world->create_node(world, "Child", parent);
    world->destroy_node(world, child);
    
    ke_hierarchy_component* ph = (ke_hierarchy_component*)ke_ecs_component_get(
        world->get_registry(world), parent, world->hierarchy_id(world));
    ASSERT_EQ(ph->first_child, KE_ENTITY_INVALID);
}

TEST_F(WorldTest, DestroyNode_Recursive_Works) {
    ke_entity e1 = world->create_node(world, "E1", world->get_root(world));
    ke_entity e2 = world->create_node(world, "E2", e1);
    
    world->destroy_node(world, e1);
    ASSERT_EQ(ke_ecs_component_get(world->get_registry(world), e2, world->hierarchy_id(world)), nullptr);
}

TEST_F(WorldTest, DestroyNode_SiblingLinks_Middle) {
    ke_entity p = world->get_root(world);
    ke_entity s1 = world->create_node(world, "S1", p);
    ke_entity s2 = world->create_node(world, "S2", p);
    ke_entity s3 = world->create_node(world, "S3", p);
    
    world->destroy_node(world, s2);
    
    ke_hierarchy_component* h3 = (ke_hierarchy_component*)ke_ecs_component_get(
        world->get_registry(world), s3, world->hierarchy_id(world));
    ASSERT_EQ(h3->next_sibling, s1);
}

TEST_F(WorldTest, DestroyNode_SiblingLinks_Prev) {
    ke_entity p = world->get_root(world);
    ke_entity s1 = world->create_node(world, "S1", p);
    ke_entity s2 = world->create_node(world, "S2", p);
    
    world->destroy_node(world, s1);
    
    ke_hierarchy_component* h2 = (ke_hierarchy_component*)ke_ecs_component_get(
        world->get_registry(world), s2, world->hierarchy_id(world));
    ASSERT_EQ(h2->next_sibling, KE_ENTITY_INVALID);
}

// --- Update and Script Tests ---

TEST_F(WorldTest, Script_Lifecycle_Works) {
    ke_entity e = world->create_node(world, "ScriptNode", world->get_root(world));
    ke_script_component* s = (ke_script_component*)ke_ecs_component_add(
        world->get_registry(world), e, world->script_id(world));
    
    static bool s_started; s_started = false;
    static float s_dt; s_dt = -1.0f;
    
    s->on_start = [](ke_entity ent) -> ke_result { s_started = true; return KE_OK; };
    s->on_update = [](ke_entity ent, float dt) -> ke_result { s_dt = dt; return KE_OK; };
    
    ke_frame frame = { 0, 0.016, 0.016 };
    world->update(world, &frame);
    
    ASSERT_TRUE(s_started);
}

TEST_F(WorldTest, Script_Update_Dt_IsCorrect) {
    ke_entity e = world->create_node(world, "ScriptNode", world->get_root(world));
    ke_script_component* s = (ke_script_component*)ke_ecs_component_add(
        world->get_registry(world), e, world->script_id(world));
    
    static float s_dt; s_dt = -1.0f;
    s->on_update = [](ke_entity ent, float dt) -> ke_result { s_dt = dt; return KE_OK; };
    
    ke_frame frame = { 0, 0.016, 0.016 };
    world->update(world, &frame);
    
    ASSERT_FLOAT_EQ(s_dt, 0.016f);
}

TEST_F(WorldTest, Update_NullFrame_UsesZeroDt) {
    ke_entity e = world->create_node(world, "Node", world->get_root(world));
    ke_script_component* s = (ke_script_component*)ke_ecs_component_add(
        world->get_registry(world), e, world->script_id(world));
    
    static float s_dt; s_dt = -1.0f;
    s->on_update = [](ke_entity ent, float dt) -> ke_result { s_dt = dt; return KE_OK; };
    
    world->update(world, nullptr);
    ASSERT_FLOAT_EQ(s_dt, 0.0f);
}

// --- System Tests ---

struct MockSystemData { int updates; bool destroyed; };

TEST_F(WorldTest, AddSystem_Success) {
    ke_system sys = { nullptr, nullptr, nullptr };
    ASSERT_EQ(world->add_system(world, &sys), KE_OK);
}

TEST_F(WorldTest, AddSystem_Full_ReturnsError) {
    ke_system sys = { nullptr, nullptr, nullptr };
    for(int i=0; i<64; ++i) world->add_system(world, &sys);
    ASSERT_EQ(world->add_system(world, &sys), KE_ERROR_OUT_OF_MEMORY);
}

TEST_F(WorldTest, System_Update_Called) {
    static int s_updates; s_updates = 0;
    ke_system sys;
    sys.handle = nullptr;
    sys.update = [](ke_world* w, void* h, float dt) { s_updates++; };
    sys.destroy = nullptr;
    
    world->add_system(world, &sys);
    world->update(world, nullptr);
    
    ASSERT_EQ(s_updates, 1);
}

TEST_F(WorldTest, System_Destroy_Called) {
    static bool s_destroyed; s_destroyed = false;
    ke_system sys;
    sys.handle = nullptr;
    sys.update = nullptr;
    sys.destroy = [](void* h) { s_destroyed = true; };
    
    world->add_system(world, &sys);
    world->destroy(world);
    world = nullptr;
    
    ASSERT_TRUE(s_destroyed);
}

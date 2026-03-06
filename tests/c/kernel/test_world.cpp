#include <gtest/gtest.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/engine/frame.h>

class WorldTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_world* world = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        
        ke_world_params params = {
            .allocator = alloc,
            .renderer = nullptr,
            .window = nullptr
        };
        
        ke_result res = ke_world_create(&params, &world);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (world) {
            world->destroy(world);
        }
        if (alloc) {
            alloc->destroy(alloc);
        }
    }
};

TEST_F(WorldTest, NodeLifecycle) {
    ke_entity root = world->get_root(world);
    ASSERT_NE(root, KE_ENTITY_INVALID);
    
    ke_entity child = world->create_node(world, "Child", root);
    ASSERT_NE(child, KE_ENTITY_INVALID);
    
    ke_result res = world->destroy_node(world, child);
    ASSERT_EQ(res, KE_OK);
}

TEST_F(WorldTest, ComponentIds) {
    ASSERT_NE(world->transform_id(world), (ke_component_id)-1);
    ASSERT_NE(world->hierarchy_id(world), (ke_component_id)-1);
    ASSERT_NE(world->name_id(world), (ke_component_id)-1);
    ASSERT_NE(world->script_id(world), (ke_component_id)-1);
}

static void test_system_update(ke_world* world, void* handle, float dt) {
    bool* called = (bool*)handle;
    *called = true;
}

TEST_F(WorldTest, AddSystem) {
    bool called = false;
    ke_system sys = {
        .handle = &called,
        .update = test_system_update,
        .destroy = nullptr
    };
    
    ke_result res = world->add_system(world, &sys);
    ASSERT_EQ(res, KE_OK);
    
    ke_frame frame = { .delta_time = 0.016f };
    world->update(world, &frame);
    
    ASSERT_TRUE(called);
}

TEST_F(WorldTest, GetRegistry) {
    ke_ecs_registry* reg = world->get_registry(world);
    ASSERT_NE(reg, nullptr);
}

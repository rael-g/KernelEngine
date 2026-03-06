#include <gtest/gtest.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/context/allocator.h>

class EcsTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_ecs_registry* registry = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_ecs_registry_create(alloc, &registry);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (registry) {
            ke_ecs_registry_destroy(registry);
        }
        if (alloc) {
            alloc->destroy(alloc);
        }
    }
};

struct test_component {
    int x;
    float y;
};

TEST_F(EcsTest, EntityLifecycle) {
    ke_entity e1 = ke_ecs_entity_create(registry);
    ke_entity e2 = ke_ecs_entity_create(registry);
    ASSERT_NE(e1, KE_ENTITY_INVALID);
    ASSERT_NE(e2, KE_ENTITY_INVALID);
    ASSERT_NE(e1, e2);
    
    ke_ecs_entity_destroy(registry, e1);
    // Entity 1 should be reusable eventually or marked as invalid.
}

TEST_F(EcsTest, ComponentRegistration) {
    ke_component_id cid = ke_ecs_component_register(registry, "Test", sizeof(test_component));
    ASSERT_NE(cid, (ke_component_id)-1);
}

TEST_F(EcsTest, AddRemoveComponent) {
    ke_component_id cid = ke_ecs_component_register(registry, "Test", sizeof(test_component));
    ke_entity e = ke_ecs_entity_create(registry);
    
    test_component* comp = (test_component*)ke_ecs_component_add(registry, e, cid);
    ASSERT_NE(comp, nullptr);
    comp->x = 10;
    comp->y = 20.0f;
    
    test_component* retrieved = (test_component*)ke_ecs_component_get(registry, e, cid);
    ASSERT_EQ(retrieved, comp);
    ASSERT_EQ(retrieved->x, 10);
    
    ke_ecs_component_remove(registry, e, cid);
    ASSERT_EQ(ke_ecs_component_get(registry, e, cid), nullptr);
}

TEST_F(EcsTest, Query) {
    ke_component_id cid = ke_ecs_component_register(registry, "Test", sizeof(test_component));
    ke_entity e1 = ke_ecs_entity_create(registry);
    ke_entity e2 = ke_ecs_entity_create(registry);
    
    ke_ecs_component_add(registry, e1, cid);
    ke_ecs_component_add(registry, e2, cid);
    
    ke_entity* entities = nullptr;
    void* data = nullptr;
    size_t count = 0;
    ke_ecs_registry_query(registry, cid, &entities, &data, &count);
    
    ASSERT_EQ(count, 2);
    ASSERT_NE(entities, nullptr);
    ASSERT_NE(data, nullptr);
    
    // Check if both entities are present in any order
    bool found_e1 = false, found_e2 = false;
    for (size_t i = 0; i < count; ++i) {
        if (entities[i] == e1) found_e1 = true;
        if (entities[i] == e2) found_e2 = true;
    }
    ASSERT_TRUE(found_e1);
    ASSERT_TRUE(found_e2);
}

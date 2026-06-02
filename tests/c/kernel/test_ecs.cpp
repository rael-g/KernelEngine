#include <gtest/gtest.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/ke_ecs.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <string.h>

class EcsTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_ecs_registry* reg = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_ecs_registry_create(alloc, &reg);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (reg) ke_ecs_registry_destroy(reg);
        if (alloc) alloc->destroy(alloc);
    }
};

// --- Registry Lifecycle ---

TEST(EcsInitTest, Create_NullArgs_ReturnsInvalidArgument) {
    ke_allocator* a = ke_allocator_malloc_create();
    ke_ecs_registry* r = nullptr;
    ASSERT_EQ(ke_ecs_registry_create(nullptr, &r), KE_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(ke_ecs_registry_create(a, nullptr), KE_ERROR_INVALID_ARGUMENT);
    a->destroy(a);
}

static void* fail_alloc(ke_allocator* alloc, size_t size, size_t alignment) { return nullptr; }
static void safe_free(ke_allocator* alloc, void* ptr) { if (ptr) free(ptr); }

TEST(EcsInitTest, Create_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.free = safe_free;
    ke_ecs_registry* r = nullptr;
    ASSERT_EQ(ke_ecs_registry_create(&fa, &r), KE_ERROR_OUT_OF_MEMORY);
}

static int alloc_count = 0;
static void* fail_second_alloc(ke_allocator* alloc, size_t size, size_t alignment) {
    if (alloc_count++ == 0) return malloc(size);
    return nullptr;
}

TEST(EcsInitTest, Create_InternalAllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_second_alloc;
    fa.free = safe_free;
    alloc_count = 0;
    ke_ecs_registry* r = nullptr;
    ASSERT_EQ(ke_ecs_registry_create(&fa, &r), KE_ERROR_OUT_OF_MEMORY);
}

TEST(EcsInitTest, Destroy_NullRegistry_DoesNotCrash) {
    ke_ecs_registry_destroy(nullptr);
    SUCCEED();
}

// --- Entity Lifecycle ---

TEST_F(EcsTest, EntityCreate_NullRegistry_ReturnsInvalid) {
    ASSERT_EQ(ke_ecs_entity_create(nullptr), KE_ENTITY_INVALID);
}

TEST_F(EcsTest, EntityCreate_ReturnsValidEntity) {
    ASSERT_NE(ke_ecs_entity_create(reg), KE_ENTITY_INVALID);
}

TEST_F(EcsTest, EntityCreate_ReturnsUniqueEntities) {
    ke_entity e1 = ke_ecs_entity_create(reg);
    ke_entity e2 = ke_ecs_entity_create(reg);
    ASSERT_NE(e1, e2);
}

TEST_F(EcsTest, EntityDestroy_NullRegistry_DoesNotCrash) {
    ke_ecs_entity_destroy(nullptr, 1);
    SUCCEED();
}

TEST_F(EcsTest, EntityDestroy_InvalidEntity_DoesNotCrash) {
    ke_ecs_entity_destroy(reg, KE_ENTITY_INVALID);
    SUCCEED();
}

TEST_F(EcsTest, EntityDestroy_RemovesAllComponents) {
    ke_entity e = ke_ecs_entity_create(reg);
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(int));
    ke_ecs_component_add(reg, e, c);
    
    ke_ecs_entity_destroy(reg, e);
    ASSERT_EQ(ke_ecs_component_get(reg, e, c), nullptr);
}

// --- Component Registration ---

TEST_F(EcsTest, ComponentRegister_NullRegistry_ReturnsError) {
    ASSERT_EQ(ke_ecs_component_register(nullptr, "Test", 4), (ke_component_id)-1);
}

TEST_F(EcsTest, ComponentRegister_NullName_ReturnsError) {
    ASSERT_EQ(ke_ecs_component_register(reg, nullptr, 4), (ke_component_id)-1);
}

TEST_F(EcsTest, ComponentRegister_ReturnsValidId) {
    ASSERT_NE(ke_ecs_component_register(reg, "Test", 4), (ke_component_id)-1);
}

// --- Component Add/Get ---

struct TestComp { int x; int y; };

TEST_F(EcsTest, ComponentAdd_NullRegistry_ReturnsNull) {
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(TestComp));
    ASSERT_EQ(ke_ecs_component_add(nullptr, 1, c), nullptr);
}

TEST_F(EcsTest, ComponentAdd_InvalidEntity_ReturnsNull) {
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(TestComp));
    ASSERT_EQ(ke_ecs_component_add(reg, KE_ENTITY_INVALID, c), nullptr);
}

TEST_F(EcsTest, ComponentAdd_InvalidComponent_ReturnsNull) {
    ke_entity e = ke_ecs_entity_create(reg);
    ASSERT_EQ(ke_ecs_component_add(reg, e, 999), nullptr);
}

TEST_F(EcsTest, ComponentAdd_ReturnsNonNull) {
    ke_entity e = ke_ecs_entity_create(reg);
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(TestComp));
    ASSERT_NE(ke_ecs_component_add(reg, e, c), nullptr);
}

TEST_F(EcsTest, ComponentAdd_ExistingComponent_ReturnsSamePointer) {
    ke_entity e = ke_ecs_entity_create(reg);
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(TestComp));
    void* p1 = ke_ecs_component_add(reg, e, c);
    void* p2 = ke_ecs_component_add(reg, e, c);
    ASSERT_EQ(p1, p2);
}

TEST_F(EcsTest, ComponentAdd_Resize_Works) {
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(int));
    // Initial capacity is 32. Add 33 components to trigger realloc
    for(int i=0; i<33; ++i) {
        ke_entity e = ke_ecs_entity_create(reg);
        ASSERT_NE(ke_ecs_component_add(reg, e, c), nullptr);
    }
    SUCCEED();
}

TEST_F(EcsTest, ComponentGet_ReturnsAddedComponent) {
    ke_entity e = ke_ecs_entity_create(reg);
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(TestComp));
    TestComp* added = (TestComp*)ke_ecs_component_add(reg, e, c);
    added->x = 100;
    
    TestComp* retrieved = (TestComp*)ke_ecs_component_get(reg, e, c);
    ASSERT_EQ(retrieved->x, 100);
}

TEST_F(EcsTest, ComponentGet_NonExistent_ReturnsNull) {
    ke_entity e = ke_ecs_entity_create(reg);
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(TestComp));
    ASSERT_EQ(ke_ecs_component_get(reg, e, c), nullptr);
}

TEST_F(EcsTest, ComponentGet_InvalidArgs_ReturnsNull) {
    ASSERT_EQ(ke_ecs_component_get(nullptr, 1, 0), nullptr);
    ASSERT_EQ(ke_ecs_component_get(reg, KE_ENTITY_INVALID, 0), nullptr);
    ASSERT_EQ(ke_ecs_component_get(reg, 1, 999), nullptr);
}

// --- Component Remove ---

TEST_F(EcsTest, ComponentRemove_NullRegistry_DoesNotCrash) {
    ke_ecs_component_remove(nullptr, 1, 0);
    SUCCEED();
}

TEST_F(EcsTest, ComponentRemove_InvalidEntity_DoesNotCrash) {
    ke_ecs_component_remove(reg, KE_ENTITY_INVALID, 0);
    SUCCEED();
}

TEST_F(EcsTest, ComponentRemove_InvalidComponent_DoesNotCrash) {
    ke_ecs_component_remove(reg, 1, 999);
    SUCCEED();
}

TEST_F(EcsTest, ComponentRemove_NonExistent_DoesNotCrash) {
    ke_entity e = ke_ecs_entity_create(reg);
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(int));
    ke_ecs_component_remove(reg, e, c);
    SUCCEED();
}

TEST_F(EcsTest, ComponentRemove_LastElement_Works) {
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(int));
    ke_entity e = ke_ecs_entity_create(reg);
    ke_ecs_component_add(reg, e, c);
    
    ke_ecs_component_remove(reg, e, c);
    ASSERT_EQ(ke_ecs_component_get(reg, e, c), nullptr);
}

TEST_F(EcsTest, ComponentRemove_MiddleElement_Works) {
    ke_component_id c = ke_ecs_component_register(reg, "Comp", sizeof(int));
    ke_entity e1 = ke_ecs_entity_create(reg);
    ke_entity e2 = ke_ecs_entity_create(reg);
    ke_entity e3 = ke_ecs_entity_create(reg);
    
    *(int*)ke_ecs_component_add(reg, e1, c) = 1;
    *(int*)ke_ecs_component_add(reg, e2, c) = 2;
    *(int*)ke_ecs_component_add(reg, e3, c) = 3;
    
    // Remove middle (e2)
    ke_ecs_component_remove(reg, e2, c);
    
    ASSERT_EQ(ke_ecs_component_get(reg, e2, c), nullptr);
    ASSERT_EQ(*(int*)ke_ecs_component_get(reg, e1, c), 1);
    ASSERT_EQ(*(int*)ke_ecs_component_get(reg, e3, c), 3);
}

// --- Sparse Set VTable Tests ---

TEST_F(EcsTest, SparseSet_Create_NullArgs_ReturnsInvalidArgument) {
    ke_ecs* ecs = nullptr;
    ASSERT_EQ(ke_ecs_sparse_set_create(nullptr, alloc, &ecs), KE_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(ke_ecs_sparse_set_create(reg, nullptr, &ecs), KE_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(ke_ecs_sparse_set_create(reg, alloc, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(EcsTest, SparseSet_EntityCreate_Works) {
    ke_ecs* ecs = nullptr;
    ke_ecs_sparse_set_create(reg, alloc, &ecs);
    
    ke_entity e = ecs->entity_create(ecs);
    ASSERT_NE(e, KE_ENTITY_INVALID);
    
    ecs->destroy(ecs);
}

TEST_F(EcsTest, SparseSet_ComponentWorkflow_Works) {
    ke_ecs* ecs = nullptr;
    ke_ecs_sparse_set_create(reg, alloc, &ecs);
    
    ke_component_id cid = ecs->component_register(ecs, "VTableComp", sizeof(int));
    ke_entity e = ecs->entity_create(ecs);
    
    int* data = (int*)ecs->component_add(ecs, e, cid);
    *data = 123;
    
    ASSERT_EQ(*(int*)ecs->component_get(ecs, e, cid), 123);
    
    ke_entity* ents; void* qdata; size_t count;
    ecs->query(ecs, cid, &ents, &qdata, &count);
    ASSERT_EQ(count, 1);
    ASSERT_EQ(((int*)qdata)[0], 123);
    
    ecs->component_remove(ecs, e, cid);
    ASSERT_EQ(ecs->component_get(ecs, e, cid), nullptr);
    
    ecs->entity_destroy(ecs, e);
    
    ecs->destroy(ecs);
}


#include <gtest/gtest.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/variant.h>
#include <kernel_engine/ecs/component_field.h>
#include <kernel_engine/allocator/allocator.h>
#include <string.h>
#include <stddef.h>

class EcsTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_ecs_registry* reg = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_ecs_registry_create(alloc, &reg, NULL);
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
    ASSERT_EQ(ke_ecs_registry_create(nullptr, &r, NULL), KE_ERROR);
    ASSERT_EQ(ke_ecs_registry_create(a, nullptr, NULL), KE_ERROR);
    a->destroy(a);
}

static void* fail_alloc(ke_allocator* alloc, size_t size, size_t alignment) { return nullptr; }
static void safe_free(ke_allocator* alloc, void* ptr) { if (ptr) free(ptr); }

TEST(EcsInitTest, Create_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.free = safe_free;
    ke_ecs_registry* r = nullptr;
    ASSERT_EQ(ke_ecs_registry_create(&fa, &r, NULL), KE_ERROR);
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
    ASSERT_EQ(ke_ecs_registry_create(&fa, &r, NULL), KE_ERROR);
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
    ASSERT_EQ(ke_ecs_sparse_set_create(nullptr, alloc, &ecs), KE_ERROR);
    ASSERT_EQ(ke_ecs_sparse_set_create(reg, nullptr, &ecs), KE_ERROR);
    ASSERT_EQ(ke_ecs_sparse_set_create(reg, alloc, nullptr), KE_ERROR);
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

// ── Phase 1: ke_ecs_component_register_v2 / lookup / apply_variant ──────────

namespace {
struct PhaseOneComp {
    int32_t  i;
    float    f;
    ke_vec3  pos;
    uint8_t  flag;
    const char *label;
};
}

TEST_F(EcsTest, RegisterV2_StoresFields_LookupReturnsThem) {
    ke_component_field fields[] = {
        {"i",     KE_VARIANT_INT,    (uint32_t)offsetof(PhaseOneComp, i)},
        {"f",     KE_VARIANT_FLOAT,  (uint32_t)offsetof(PhaseOneComp, f)},
        {"pos",   KE_VARIANT_VEC3,   (uint32_t)offsetof(PhaseOneComp, pos)},
        {"flag",  KE_VARIANT_BOOL,   (uint32_t)offsetof(PhaseOneComp, flag)},
        {"label", KE_VARIANT_STRING, (uint32_t)offsetof(PhaseOneComp, label)},
    };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "test_comp",
                                                        sizeof(PhaseOneComp),
                                                        fields, 5);
    ASSERT_NE(cid, KE_COMPONENT_INVALID);

    ke_component_meta meta{};
    ASSERT_EQ(ke_ecs_component_lookup(reg, "test_comp", &meta, NULL), KE_OK);
    EXPECT_EQ(meta.cid, cid);
    EXPECT_EQ(meta.size, sizeof(PhaseOneComp));
    EXPECT_EQ(meta.field_count, 5u);
}

TEST_F(EcsTest, Lookup_UnknownName_ReturnsNotFound) {
    ke_component_meta meta{};
    EXPECT_EQ(ke_ecs_component_lookup(reg, "nope", &meta, NULL), KE_ERROR);
}

TEST_F(EcsTest, RegisterLegacy_HasNoFields) {
    ke_component_id cid = ke_ecs_component_register(reg, "opaque", sizeof(int));
    ASSERT_NE(cid, KE_COMPONENT_INVALID);
    ke_component_meta meta{};
    ASSERT_EQ(ke_ecs_component_lookup(reg, "opaque", &meta, NULL), KE_OK);
    EXPECT_EQ(meta.field_count, 0u);
}

TEST_F(EcsTest, ApplyVariant_AllSupportedTypes_WrittenAtCorrectOffsets) {
    ke_component_field fields[] = {
        {"i",     KE_VARIANT_INT,    (uint32_t)offsetof(PhaseOneComp, i)},
        {"f",     KE_VARIANT_FLOAT,  (uint32_t)offsetof(PhaseOneComp, f)},
        {"pos",   KE_VARIANT_VEC3,   (uint32_t)offsetof(PhaseOneComp, pos)},
        {"flag",  KE_VARIANT_BOOL,   (uint32_t)offsetof(PhaseOneComp, flag)},
        {"label", KE_VARIANT_STRING, (uint32_t)offsetof(PhaseOneComp, label)},
    };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "test_comp",
                                                        sizeof(PhaseOneComp),
                                                        fields, 5);
    ke_entity e = ke_ecs_entity_create(reg);
    auto *comp = (PhaseOneComp *)ke_ecs_component_add(reg, e, cid);

    ke_variant vi = ke_variant_int(42);
    ke_variant vf = ke_variant_float(1.5f);
    ke_variant vv = ke_variant_vec3(1.f, 2.f, 3.f);
    ke_variant vb = ke_variant_bool(true);
    ke_variant vs = ke_variant_string("hello");

    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "i", &vi, NULL), KE_OK);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "f", &vf, NULL), KE_OK);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "pos", &vv, NULL), KE_OK);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "flag", &vb, NULL), KE_OK);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "label", &vs, NULL), KE_OK);

    EXPECT_EQ(comp->i, 42);
    EXPECT_FLOAT_EQ(comp->f, 1.5f);
    EXPECT_FLOAT_EQ(comp->pos.x, 1.f);
    EXPECT_EQ(comp->flag, 1);
    EXPECT_STREQ(comp->label, "hello");
}

TEST_F(EcsTest, ApplyVariant_StringWithSize_CopiesIntoFixedBuffer) {
    struct BufComp { char primitive[8]; };
    ke_component_field fields[] = {
        {"primitive", KE_VARIANT_STRING, (uint32_t)offsetof(BufComp, primitive), 8},
    };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "buf", sizeof(BufComp), fields, 1);
    ke_entity e = ke_ecs_entity_create(reg);
    auto *c = (BufComp *)ke_ecs_component_add(reg, e, cid);

    ke_variant v = ke_variant_string("cube");
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "primitive", &v, NULL), KE_OK);
    EXPECT_STREQ(c->primitive, "cube");
}

TEST_F(EcsTest, ApplyVariant_Vec2_Works) {
    struct VecComp { ke_vec2 v; };
    ke_component_field fields[] = { {"v", KE_VARIANT_VEC2, 0} };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "vc", sizeof(VecComp), fields, 1);
    ke_entity e = ke_ecs_entity_create(reg);
    auto *c = (VecComp *)ke_ecs_component_add(reg, e, cid);

    ke_variant v = ke_variant_vec2(10.f, 20.f);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "v", &v, NULL), KE_OK);
    EXPECT_FLOAT_EQ(c->v.x, 10.f);
    EXPECT_FLOAT_EQ(c->v.y, 20.f);
}

TEST_F(EcsTest, ApplyVariant_Vec4_Works) {
    struct VecComp { ke_vec4 v; };
    ke_component_field fields[] = { {"v", KE_VARIANT_VEC4, 0} };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "vc", sizeof(VecComp), fields, 1);
    ke_entity e = ke_ecs_entity_create(reg);
    auto *c = (VecComp *)ke_ecs_component_add(reg, e, cid);

    ke_variant v = ke_variant_vec4(1.f, 2.f, 3.f, 4.f);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "v", &v, NULL), KE_OK);
    EXPECT_FLOAT_EQ(c->v.x, 1.f);
    EXPECT_FLOAT_EQ(c->v.w, 4.f);
}

TEST_F(EcsTest, ApplyVariant_Quat_Works) {
    struct QuatComp { ke_quat q; };
    ke_component_field fields[] = { {"q", KE_VARIANT_QUAT, 0} };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "qc", sizeof(QuatComp), fields, 1);
    ke_entity e = ke_ecs_entity_create(reg);
    auto *c = (QuatComp *)ke_ecs_component_add(reg, e, cid);

    ke_variant v = ke_variant_quat(0.f, 0.f, 0.f, 1.f);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "q", &v, NULL), KE_OK);
    EXPECT_FLOAT_EQ(c->q.w, 1.f);
}

TEST_F(EcsTest, ApplyVariant_FloatToInt_Denied) {
    struct IntComp { int32_t i; };
    ke_component_field fields[] = { {"i", KE_VARIANT_INT, 0} };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "ic", sizeof(IntComp), fields, 1);
    ke_entity e = ke_ecs_entity_create(reg);
    ke_ecs_component_add(reg, e, cid);

    ke_variant v = ke_variant_float(42.7f);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "i", &v, NULL), KE_ERROR);
}

TEST_F(EcsTest, ApplyVariant_UnknownField_ReturnsNotFound) {
    struct Dummy { int x; };
    ke_component_field fields[] = { {"x", KE_VARIANT_INT, 0} };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "d", sizeof(Dummy), fields, 1);
    ke_entity e = ke_ecs_entity_create(reg);
    ke_ecs_component_add(reg, e, cid);

    ke_variant v = ke_variant_int(1);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "y", &v, NULL), KE_ERROR);
}

TEST_F(EcsTest, ApplyVariant_Bool_Works) {
    struct BoolComp { bool b; };
    ke_component_field fields[] = { {"b", KE_VARIANT_BOOL, 0} };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "bc", sizeof(BoolComp), fields, 1);
    ke_entity e = ke_ecs_entity_create(reg);
    auto *c = (BoolComp *)ke_ecs_component_add(reg, e, cid);

    ke_variant v = ke_variant_bool(true);
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "b", &v, NULL), KE_OK);
    EXPECT_TRUE(c->b);
}

TEST_F(EcsTest, ApplyVariant_String_Works) {
    struct StringComp { char s[16]; };
    ke_component_field fields[] = { {"s", KE_VARIANT_STRING, 0, 16} };
    ke_component_id cid = ke_ecs_component_register_v2(reg, "sc", sizeof(StringComp), fields, 1);
    ke_entity e = ke_ecs_entity_create(reg);
    auto *c = (StringComp *)ke_ecs_component_add(reg, e, cid);

    ke_variant v = ke_variant_string("hello");
    EXPECT_EQ(ke_ecs_component_apply_variant(reg, e, cid, "s", &v, NULL), KE_OK);
    EXPECT_STREQ(c->s, "hello");
}

TEST_F(EcsTest, RegistryQuery_InvalidComponent_ReturnsNull) {
    ke_entity *ents; void *data; size_t count;
    ke_ecs_registry_query(reg, 999, &ents, &data, &count);
    EXPECT_EQ(ents, nullptr);
    EXPECT_EQ(data, nullptr);
    EXPECT_EQ(count, 0u);
}

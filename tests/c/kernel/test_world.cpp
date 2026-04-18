#include <gtest/gtest.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/engine/frame.h>
#include <string.h>

class WorldTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_world*     world = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_world_params params = { alloc };
        ke_result res = ke_world_create(&params, &world);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (world) world->destroy(world);
        if (alloc) alloc->destroy(alloc);
    }

    // Creates an entity with transform + hierarchy (mirrors Scene::CreateEntityWithHierarchy)
    ke_entity make_entity(const char* name, ke_entity parent) {
        ke_ecs_registry* reg = world->get_registry(world);
        ke_entity entity = ke_ecs_entity_create(reg);

        ke_transform_component* t = (ke_transform_component*)ke_ecs_component_add(
            reg, entity, world->transform_id(world));
        if (t) {
            t->position = {0.f, 0.f, 0.f};
            t->rotation = {0.f, 0.f, 0.f, 1.f};
            t->scale    = {1.f, 1.f, 1.f};
        }

        ke_hierarchy_component* h = (ke_hierarchy_component*)ke_ecs_component_add(
            reg, entity, world->hierarchy_id(world));
        if (h) {
            h->parent       = parent;
            h->first_child  = KE_ENTITY_INVALID;
            h->next_sibling = KE_ENTITY_INVALID;
            h->prev_sibling = KE_ENTITY_INVALID;

            if (parent != KE_ENTITY_INVALID) {
                ke_hierarchy_component* ph = (ke_hierarchy_component*)ke_ecs_component_get(
                    reg, parent, world->hierarchy_id(world));
                if (ph) {
                    h->next_sibling = ph->first_child;
                    ph->first_child = entity;
                }
            }
        }

        return entity;
    }
};

// ── Creation tests ─────────────────────────────────────────────────────────────

TEST(WorldInitTest, Create_NullArgs_ReturnsInvalidArgument) {
    ke_world* w = nullptr;
    ASSERT_EQ(ke_world_create(nullptr, &w), KE_ERROR_INVALID_ARGUMENT);
}

TEST(WorldInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_world* w = nullptr;
    ke_world_params params = { nullptr };
    ASSERT_EQ(ke_world_create(&params, &w), KE_ERROR_INVALID_ARGUMENT);
}

static void* fail_alloc(ke_allocator* alloc, size_t size, size_t alignment) { return nullptr; }
static void  safe_free (ke_allocator* alloc, void* ptr)                     { if (ptr) free(ptr); }

TEST(WorldInitTest, Create_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.free  = safe_free;
    ke_world* w = nullptr;
    ke_world_params params = { &fa };
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
    fa.free  = safe_free;
    alloc_count = 0;
    ke_world* w = nullptr;
    ke_world_params params = { &fa };
    ASSERT_EQ(ke_world_create(&params, &w), KE_ERROR_OUT_OF_MEMORY);
}

// ── Component ID tests ─────────────────────────────────────────────────────────

TEST_F(WorldTest, BuiltinComponentIds_AreDistinct) {
    ASSERT_NE(world->transform_id(world), world->hierarchy_id(world));
    ASSERT_NE(world->hierarchy_id(world), world->name_id(world));
    ASSERT_NE(world->name_id(world),      world->script_id(world));
}

// ── Script system tests ────────────────────────────────────────────────────────

TEST_F(WorldTest, Script_Lifecycle_Works) {
    ke_ecs_registry* reg = world->get_registry(world);
    ke_entity e = ke_ecs_entity_create(reg);

    ke_script_component* s = (ke_script_component*)ke_ecs_component_add(
        reg, e, world->script_id(world));

    static bool s_started; s_started = false;
    s->on_start  = [](ke_entity ent) -> ke_result { s_started = true; return KE_OK; };
    s->on_update = [](ke_entity ent, float dt) -> ke_result { return KE_OK; };

    ke_frame frame = { 0, 0.016, 0.016 };
    world->update(world, &frame);
    ASSERT_TRUE(s_started);
}

TEST_F(WorldTest, Script_Update_Dt_IsCorrect) {
    ke_ecs_registry* reg = world->get_registry(world);
    ke_entity e = ke_ecs_entity_create(reg);

    ke_script_component* s = (ke_script_component*)ke_ecs_component_add(
        reg, e, world->script_id(world));

    static float s_dt; s_dt = -1.f;
    s->on_update = [](ke_entity ent, float dt) -> ke_result { s_dt = dt; return KE_OK; };

    ke_frame frame = { 0, 0.016, 0.016 };
    world->update(world, &frame);
    ASSERT_FLOAT_EQ(s_dt, 0.016f);
}

TEST_F(WorldTest, Update_NullFrame_UsesZeroDt) {
    ke_ecs_registry* reg = world->get_registry(world);
    ke_entity e = ke_ecs_entity_create(reg);

    ke_script_component* s = (ke_script_component*)ke_ecs_component_add(
        reg, e, world->script_id(world));

    static float s_dt; s_dt = -1.f;
    s->on_update = [](ke_entity ent, float dt) -> ke_result { s_dt = dt; return KE_OK; };

    world->update(world, nullptr);
    ASSERT_FLOAT_EQ(s_dt, 0.0f);
}

// ── Transform system tests ─────────────────────────────────────────────────────

TEST_F(WorldTest, Transform_Root_WorldMatrixUpdated) {
    ke_entity root = make_entity("Root", KE_ENTITY_INVALID);

    ke_transform_component* t = (ke_transform_component*)ke_ecs_component_get(
        world->get_registry(world), root, world->transform_id(world));
    t->position = {1.f, 2.f, 3.f};

    world->update(world, nullptr);

    ASSERT_FLOAT_EQ(t->world_matrix.m[12], 1.f);
    ASSERT_FLOAT_EQ(t->world_matrix.m[13], 2.f);
    ASSERT_FLOAT_EQ(t->world_matrix.m[14], 3.f);
}

TEST_F(WorldTest, Transform_Child_InheritsParentMatrix) {
    ke_entity parent = make_entity("Parent", KE_ENTITY_INVALID);
    ke_entity child  = make_entity("Child",  parent);

    ke_ecs_registry* reg = world->get_registry(world);

    ke_transform_component* tp = (ke_transform_component*)ke_ecs_component_get(
        reg, parent, world->transform_id(world));
    tp->position = {5.f, 0.f, 0.f};

    ke_transform_component* tc = (ke_transform_component*)ke_ecs_component_get(
        reg, child, world->transform_id(world));
    tc->position = {1.f, 0.f, 0.f};

    world->update(world, nullptr);

    // Child world position should be parent(5) + child(1) = 6
    ASSERT_FLOAT_EQ(tc->world_matrix.m[12], 6.f);
}

// ── System registration tests ──────────────────────────────────────────────────

TEST_F(WorldTest, AddSystem_Success) {
    ke_system sys = { nullptr, nullptr, nullptr };
    ASSERT_EQ(world->add_system(world, &sys), KE_OK);
}

TEST_F(WorldTest, AddSystem_Full_ReturnsError) {
    ke_system sys = { nullptr, nullptr, nullptr };
    for (int i = 0; i < 64; ++i) world->add_system(world, &sys);
    ASSERT_EQ(world->add_system(world, &sys), KE_ERROR_OUT_OF_MEMORY);
}

TEST_F(WorldTest, System_Update_Called) {
    static int s_updates; s_updates = 0;
    ke_system sys;
    sys.handle  = nullptr;
    sys.update  = [](ke_world* w, void* h, float dt) { s_updates++; };
    sys.destroy = nullptr;

    world->add_system(world, &sys);
    world->update(world, nullptr);
    ASSERT_EQ(s_updates, 1);
}

TEST_F(WorldTest, System_Destroy_Called) {
    static bool s_destroyed; s_destroyed = false;
    ke_system sys;
    sys.handle  = nullptr;
    sys.update  = nullptr;
    sys.destroy = [](void* h) { s_destroyed = true; };

    world->add_system(world, &sys);
    world->destroy(world);
    world = nullptr;
    ASSERT_TRUE(s_destroyed);
}

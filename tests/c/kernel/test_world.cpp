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

// ── System registration tests ──────────────────────────────────────────────────

TEST_F(WorldTest, AddSystem_Success) {
    ke_system_params sys{};
    sys.name = "Test";
    sys.update = [](void*, ke_world*, float, ke_frame_packet*) {};
    ASSERT_EQ(world->add_system(world, &sys), KE_OK);
}

// ── Transform tests ───────────────────────────────────────────────────────────

TEST_F(WorldTest, Transform_HierarchyUpdate_Works) {
    ke_entity parent = make_entity("P", KE_ENTITY_INVALID);
    ke_entity child  = make_entity("C", parent);

    ke_ecs_registry* reg = world->get_registry(world);
    ke_transform_component* pt = (ke_transform_component*)ke_ecs_component_get(reg, parent, world->transform_id(world));
    ke_transform_component* ct = (ke_transform_component*)ke_ecs_component_get(reg, child, world->transform_id(world));

    pt->position = { 10.f, 0.f, 0.f };
    ct->position = { 5.f, 0.f, 0.f };

    world->update(world, nullptr);

    // Row-major: world = local * parent.
    // Child local (5,0,0) * Parent (10,0,0) = (15,0,0)
    ASSERT_FLOAT_EQ(ct->world_matrix.m[12], 15.f);
}

// ── System dependency tests ──────────────────────────────────────────────────

TEST_F(WorldTest, AddSystem_ParallelExecution_Works) {
    static int s_c1, s_c2;
    s_c1 = 0; s_c2 = 0;
    
    uint32_t r1[] = {1};
    uint32_t r2[] = {2};

    ke_system_params sys1{};
    sys1.name = "S1";
    sys1.reads = r1; sys1.read_count = 1;
    sys1.update = [](void*, ke_world*, float, ke_frame_packet*) { s_c1++; };

    ke_system_params sys2{};
    sys2.name = "S2";
    sys2.reads = r2; sys2.read_count = 1; // Different reads, no conflict
    sys2.update = [](void*, ke_world*, float, ke_frame_packet*) { s_c2++; };

    world->add_system(world, &sys1);
    world->add_system(world, &sys2);
    
    world->update(world, nullptr);
    
    ASSERT_EQ(s_c1, 1);
    ASSERT_EQ(s_c2, 1);
}

TEST_F(WorldTest, AddSystem_ConflictingSystems_RunInSerial) {
    static int s_val; s_val = 0;
    uint32_t c1[] = {10};

    ke_system_params sys1{};
    sys1.name = "Writer";
    sys1.writes = c1; sys1.write_count = 1;
    sys1.update = [](void*, ke_world*, float, ke_frame_packet*) { s_val = 42; };

    ke_system_params sys2{};
    sys2.name = "Reader";
    sys2.reads = c1; sys2.read_count = 1; // Conflict on CID 10
    sys2.update = [](void*, ke_world*, float, ke_frame_packet*) { if (s_val == 42) s_val = 99; };

    world->add_system(world, &sys1);
    world->add_system(world, &sys2);
    
    world->update(world, nullptr);
    
    // If they run in order (Serial), Writer runs then Reader runs -> 99.
    ASSERT_EQ(s_val, 99);
}

TEST_F(WorldTest, AddSystem_SerialBarrier_Works) {
    static int s_updates; s_updates = 0;
    ke_system_params sys{};
    sys.name = "Barrier";
    sys.read_count = 0; sys.write_count = 0; // Empty system acts as barrier
    sys.update = [](void*, ke_world*, float, ke_frame_packet*) { s_updates++; };

    world->add_system(world, &sys);
    world->update(world, nullptr);
    ASSERT_EQ(s_updates, 1);
}

// ── Notify destroy tests ──────────────────────────────────────────────────────

TEST_F(WorldTest, NotifyDestroy_CallsOnDestroy) {
    ke_ecs_registry* reg = world->get_registry(world);
    ke_entity e = ke_ecs_entity_create(reg);
    ke_script_component* s = (ke_script_component*)ke_ecs_component_add(reg, e, world->script_id(world));

    static bool s_destroyed; s_destroyed = false;
    s->on_destroy = [](ke_entity ent) { s_destroyed = true; return KE_OK; };

    ASSERT_EQ(ke_world_notify_destroy(world, e), KE_OK);
    ASSERT_TRUE(s_destroyed);
}

TEST_F(WorldTest, NotifyDestroy_SafeOnNullOrMissing) {
    ASSERT_EQ(ke_world_notify_destroy(nullptr, 1), KE_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(ke_world_notify_destroy(world, 0), KE_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(ke_world_notify_destroy(world, 999), KE_OK); // Non-existent entity
}


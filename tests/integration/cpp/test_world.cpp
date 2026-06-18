#include <gtest/gtest.h>

#include <kernel_engine/framework/world.h>
#include <kernel_engine/framework/world_create.h>
#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/task_scheduler/enki/enki_task_scheduler.h>

namespace {

struct WorldFixture {
    ke_allocator      *allocator      = nullptr;
    ke_task_scheduler_handle task_scheduler_h{};
    ke_ecs_handle            ecs_h{};
    ke_runtime_handle        runtime_h{};
    ke_world_handle          world_h{};
    ke_world          *world          = nullptr;

    void create(const char *project_root = nullptr) {
        allocator = ke_allocator_malloc_create();
        ASSERT_EQ(ke_task_scheduler_enki_create(allocator, &task_scheduler_h, NULL), KE_OK);

        ke_ecs_flecs_params ecs_params{};
        ASSERT_EQ(ke_ecs_flecs_create(&ecs_params, &ecs_h, NULL), KE_OK);

        ke_runtime_params rt_params{};
        ASSERT_EQ(ke_runtime_create(ecs_h.ref, task_scheduler_h.ref, &rt_params, &runtime_h, NULL), KE_OK);

        ke_world_params wp{};
        wp.task_scheduler = task_scheduler_h.ref;
        wp.ecs            = ecs_h.ref;
        wp.runtime        = runtime_h.ref;
        wp.scene_tree     = nullptr;  // C-phase reintroduces; B2 ships ke_world without scene_tree
        wp.project_root   = project_root;
        ASSERT_EQ(ke_world_create(&wp, &world_h, NULL), KE_OK);
        world = world_h.ref;
        ASSERT_NE(world, nullptr);
    }

    void teardown() {
        // "Quem cria, owna": destroy in reverse-create order; world borrows the rest.
        if (world_h.ref) world_h.destroy(world_h.ref);
        if (runtime_h.ref) runtime_h.destroy(runtime_h.ref);
        if (ecs_h.ref) ecs_h.destroy(ecs_h.ref);
        if (task_scheduler_h.ref) task_scheduler_h.destroy(task_scheduler_h.ref);
    }
};

}  // namespace

TEST(WorldB2, Create_Accessors_Destroy)
{
    WorldFixture f;
    f.create("res/");

    EXPECT_NE(f.world->ecs(f.world), nullptr);
    EXPECT_NE(f.world->runtime(f.world), nullptr);
    EXPECT_EQ(f.world->scene_tree(f.world), nullptr);  // B2 transitional

    // Spawn an entity to prove ecs is functional.
    ke_ecs *ecs = f.world->ecs(f.world);
    ke_entity e = ecs->entity_create(ecs);
    EXPECT_NE(e, KE_ENTITY_INVALID);

    f.teardown();
}

TEST(WorldB2, MultiWorld_Isolation)
{
    WorldFixture wa;
    WorldFixture wb;
    wa.create();
    wb.create();

    ke_ecs *ea = wa.world->ecs(wa.world);
    ke_ecs *eb = wb.world->ecs(wb.world);
    ASSERT_NE(ea, eb);

    // Spawn one entity in each world.
    ke_entity a = ea->entity_create(ea);
    ke_entity b = eb->entity_create(eb);
    EXPECT_NE(a, KE_ENTITY_INVALID);
    EXPECT_NE(b, KE_ENTITY_INVALID);

    // Destroying one world must not invalidate the other.
    wa.teardown();

    ke_entity b2 = eb->entity_create(eb);
    EXPECT_NE(b2, KE_ENTITY_INVALID);
    EXPECT_NE(b2, b);

    wb.teardown();
}

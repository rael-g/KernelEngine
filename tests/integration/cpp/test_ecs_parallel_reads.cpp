#include <gtest/gtest.h>

#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>

// ─────────────────────────────────────────────────────────────────────────────
// Phase 0 gate for the ECS memory-safety refactor.
//
// This reproduces the exact hazard that corrupted memory in the clustered-forward
// render: two systems whose access lists only READ a component land in the SAME
// parallel wave and both touch the storage (query + per-entity get) at once.
//
// The contract says no ke_ecs storage call may run concurrently during a wave.
// The funnel's concurrency-overlap guard counts violations into
// ke_system_ctx_check_failures(). TODAY this test is RED — either the guard
// reports overlap (> 0) or the concurrent flecs access crashes the run. The ECS
// refactor (resolve queries single-threaded before the wave; bodies touch only
// resolved memory) is what turns it GREEN, and under TSan on the linux preset the
// race is reported deterministically.
// ─────────────────────────────────────────────────────────────────────────────

namespace {

struct Pos
{
    float x, y, z;
};

// The cull/shadow access pattern: query the component, then a per-entity get for
// each hit. Several ke_ecs reads per tick — two of these in one wave overlap.
void reader_body(ke_system_ctx *ctx, void *ud, float)
{
    ke_component_id cid = *static_cast<ke_component_id *>(ud);
    ke_entity      *ents = nullptr;
    void           *data = nullptr;
    size_t          count = 0;
    ke_system_ctx_query(ctx, cid, &ents, &data, &count);

    volatile float sink = 0.0f;
    for (size_t i = 0; i < count; ++i)
    {
        const void *p = ke_system_ctx_get(ctx, cid, ents[i]);
        if (p) sink += static_cast<const Pos *>(p)->x;
    }
    (void)sink;
}

}  // namespace

class EcsParallelReads : public ::testing::Test
{
protected:
    ke_scheduler_handle scheduler_h{};
    ke_ecs_handle       ecs_h{};
    ke_runtime_handle   runtime_h{};
    ke_scheduler       *scheduler = nullptr;
    ke_ecs             *ecs       = nullptr;
    ke_runtime         *runtime   = nullptr;

    void SetUp() override
    {
        scheduler_h = ke_scheduler_enki_create(NULL);
        ASSERT_NE(scheduler_h.ref, nullptr);
        scheduler = scheduler_h.ref;

        ke_ecs_flecs_params ecs_params{};
        ecs_h = ke_ecs_flecs_create(&ecs_params, NULL);
        ASSERT_NE(ecs_h.ref, nullptr);
        ecs = ecs_h.ref;

        ke_runtime_params rt_params{};
        runtime_h = ke_runtime_create(ecs, scheduler, &rt_params, NULL);
        ASSERT_NE(runtime_h.ref, nullptr);
        runtime = runtime_h.ref;
    }

    void TearDown() override
    {
        if (runtime_h.ref) runtime_h.destroy(runtime_h.ref);
        if (ecs_h.ref) ecs_h.destroy(ecs_h.ref);
        if (scheduler_h.ref) scheduler_h.destroy(scheduler_h.ref);
    }
};

TEST_F(EcsParallelReads, TwoReadersSameWave_NoConcurrentStorageAccess)
{
    static ke_component_id pos;
    pos = ecs->component_register(ecs, "pos", sizeof(Pos));
    ASSERT_NE(pos, 0u);

    for (int i = 0; i < 512; ++i)
    {
        ke_entity e = ecs->entity_create(ecs);
        Pos      *p = static_cast<Pos *>(ecs->component_add(ecs, e, pos));
        ASSERT_NE(p, nullptr);
        p->x = static_cast<float>(i);
        p->y = 0.0f;
        p->z = 0.0f;
    }

    ke_component_access read_pos[1] = {{pos, KE_ACCESS_READ}};

    ke_runtime_system_params a{};
    a.name         = "ReaderA";
    a.phase        = KE_PHASE_UPDATE;
    a.access_list  = read_pos;
    a.access_count = 1;
    a.user_data    = &pos;
    a.execute      = reader_body;

    ke_runtime_system_params b = a;
    b.name                     = "ReaderB";

    ASSERT_NE(runtime->register_system(runtime, &a, nullptr), 0u);
    ASSERT_NE(runtime->register_system(runtime, &b, nullptr), 0u);

    // Both only READ pos → no write conflict → the wave-builder must place them in
    // the SAME wave (i.e. they run in parallel). If that ever stops being true the
    // test no longer exercises the hazard.
    ke_runtime_system_params sysz[2] = {a, b};
    uint32_t                  waves[2] = {0, 0};
    uint32_t                  wave_count = 0;
    ke_runtime_debug_compute_waves(sysz, 2, waves, &wave_count);
    ASSERT_EQ(waves[0], waves[1]) << "readers must share one wave to exercise parallel reads";

    ke_system_ctx_reset_check_failures();
    for (int t = 0; t < 300; ++t)
        ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    // The gate: the storage was never touched concurrently. RED until the refactor.
    EXPECT_EQ(ke_system_ctx_check_failures(), 0u)
        << "two reader systems touched ke_ecs storage concurrently during a wave";
}

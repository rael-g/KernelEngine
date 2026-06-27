#include <gtest/gtest.h>

#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>

// Asserts the contract invariant that ke_ecs storage is never touched
// concurrently during a parallel wave. Two systems that only READ a component
// share one wave (read/read has no conflict) and both access the storage at once;
// the funnel's overlap guard must report zero concurrent-access violations.

namespace {

struct Pos
{
    float x, y, z;
};

// Reads a component through the resolved view: walk the archetype segments and
// the aligned column. No ke_ecs call happens here, so two of these in one wave
// never touch the storage concurrently.
void reader_body(ke_system_ctx *ctx, void *, float)
{
    size_t                seg_count = 0;
    const ke_ecs_segment *segs      = ke_system_ctx_view(ctx, 0, &seg_count);

    volatile float sink = 0.0f;
    for (size_t s = 0; s < seg_count; ++s)
    {
        const Pos *col = static_cast<const Pos *>(segs[s].columns[0]);
        for (size_t i = 0; i < segs[s].count; ++i)
            if (col) sink += col[i].x;
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

    ke_query_decl read_pos{};
    read_pos.terms[0]  = {pos, KE_ACCESS_READ};
    read_pos.term_count = 1;

    ke_runtime_system_params a{};
    a.name        = "ReaderA";
    a.phase       = KE_PHASE_UPDATE;
    a.queries     = &read_pos;
    a.query_count = 1;
    a.execute     = reader_body;

    ke_runtime_system_params b = a;
    b.name                     = "ReaderB";

    ASSERT_NE(runtime->register_system(runtime, &a, nullptr), 0u);
    ASSERT_NE(runtime->register_system(runtime, &b, nullptr), 0u);

    // Both only READ pos → no write conflict → the wave-builder must place them in
    // the same wave, so they run in parallel. If that stops being true the test no
    // longer exercises concurrent reads.
    ke_runtime_system_params sysz[2] = {a, b};
    uint32_t                  waves[2] = {0, 0};
    uint32_t                  wave_count = 0;
    ke_runtime_debug_compute_waves(sysz, 2, waves, &wave_count);
    ASSERT_EQ(waves[0], waves[1]) << "readers must share one wave to exercise parallel reads";

    ke_system_ctx_reset_check_failures();
    for (int t = 0; t < 300; ++t)
        ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    // The invariant: the storage was never touched concurrently during the wave.
    EXPECT_EQ(ke_system_ctx_check_failures(), 0u)
        << "two reader systems touched ke_ecs storage concurrently during a wave";
}

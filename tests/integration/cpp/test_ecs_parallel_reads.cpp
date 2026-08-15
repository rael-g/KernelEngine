#include <gtest/gtest.h>

#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>

namespace {

struct Pos
{
    float x, y, z;
};

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

}

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
    pos = ecs->component_register(ecs, "pos", sizeof(Pos), nullptr);
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

    ke_runtime_system_params sysz[2] = {a, b};
    uint32_t                  waves[2] = {0, 0};
    uint32_t                  wave_count = 0;
    ke_runtime_debug_compute_waves(sysz, 2, waves, &wave_count);
    ASSERT_EQ(waves[0], waves[1]) << "readers must share one wave to exercise parallel reads";

    for (int t = 0; t < 300; ++t)
        ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
}

namespace {
struct Vel { float x, y, z; };
double g_pv_sum = 0.0;

void posvel_body(ke_system_ctx *ctx, void *, float)
{
    size_t                seg_count = 0;
    const ke_ecs_segment *segs      = ke_system_ctx_view(ctx, 0, &seg_count);
    for (size_t s = 0; s < seg_count; ++s)
    {
        const Pos *pc = static_cast<const Pos *>(segs[s].columns[0]);
        const Vel *vc = static_cast<const Vel *>(segs[s].columns[1]);
        for (size_t i = 0; i < segs[s].count; ++i)
            g_pv_sum += static_cast<double>(pc[i].x) + static_cast<double>(vc[i].x);
    }
}
}

TEST_F(EcsParallelReads, MultiTermQuery_AlignedColumns)
{
    ke_component_id pos = ecs->component_register(ecs, "pos2", sizeof(Pos), nullptr);
    ke_component_id vel = ecs->component_register(ecs, "vel2", sizeof(Vel), nullptr);
    ASSERT_NE(pos, 0u);
    ASSERT_NE(vel, 0u);

    double expect = 0.0;
    for (int i = 0; i < 100; ++i)
    {
        ke_entity e = ecs->entity_create(ecs);
        ecs->component_add(ecs, e, pos);
        ecs->component_add(ecs, e, vel);
        Pos *p = static_cast<Pos *>(ecs->component_get(ecs, e, pos));
        Vel *v = static_cast<Vel *>(ecs->component_get(ecs, e, vel));
        ASSERT_NE(p, nullptr);
        ASSERT_NE(v, nullptr);
        p->x = static_cast<float>(i);
        v->x = static_cast<float>(i * 2);
        expect += static_cast<double>(i) + static_cast<double>(i * 2);
    }

    ke_query_decl q{};
    q.terms[0]   = {pos, KE_ACCESS_READ};
    q.terms[1]   = {vel, KE_ACCESS_READ};
    q.term_count = 2;

    ke_runtime_system_params s{};
    s.name        = "PosVel";
    s.phase       = KE_PHASE_UPDATE;
    s.queries     = &q;
    s.query_count = 1;
    s.execute     = posvel_body;
    ASSERT_NE(runtime->register_system(runtime, &s, nullptr), 0u);

    g_pv_sum = 0.0;
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    EXPECT_DOUBLE_EQ(g_pv_sum, expect) << "aligned columns must read the right per-entity data";
}

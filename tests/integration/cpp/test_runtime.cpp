#include <gtest/gtest.h>

#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>

#include <atomic>
#include <chrono>
#include <set>
#include <thread>

namespace {

struct ModuleCtx {
    std::atomic<int> load_calls{0};
    std::atomic<int> system_ticks{0};
};

bool test_module_on_load(ke_runtime *runtime, void *user_data, ke_error **out_error)
{
    auto *ctx = static_cast<ModuleCtx *>(user_data);
    ctx->load_calls.fetch_add(1, std::memory_order_relaxed);

    ke_runtime_system_params sys{};
    sys.name      = "TickCounter";
    sys.phase     = KE_PHASE_UPDATE;
    sys.user_data = user_data;
    sys.execute   = [](ke_system_ctx *, void *ud, float) {
        static_cast<ModuleCtx *>(ud)->system_ticks.fetch_add(1, std::memory_order_relaxed);
    };

    ke_system_id sid = runtime->register_system(runtime, &sys, nullptr);
    return sid != 0;
}

}

class RuntimeSpike : public ::testing::Test {
protected:
    ke_scheduler_handle scheduler_h{};
    ke_ecs_handle            ecs_h{};
    ke_runtime_handle        runtime_h{};
    ke_scheduler *scheduler = nullptr;
    ke_ecs            *ecs            = nullptr;
    ke_runtime        *runtime        = nullptr;

    void SetUp() override
    {
        scheduler_h = ke_scheduler_enki_create(NULL); ASSERT_NE(scheduler_h.ref, nullptr);
        scheduler = scheduler_h.ref;
        ASSERT_NE(scheduler, nullptr);

        ke_ecs_flecs_params ecs_params{};
        ecs_h = ke_ecs_flecs_create(&ecs_params, NULL); ASSERT_NE(ecs_h.ref, nullptr);
        ecs = ecs_h.ref;
        ASSERT_NE(ecs, nullptr);

        ke_runtime_params rt_params{};
        runtime_h = ke_runtime_create(ecs, scheduler, &rt_params, NULL); ASSERT_NE(runtime_h.ref, nullptr);
        runtime = runtime_h.ref;
        ASSERT_NE(runtime, nullptr);
    }

    void TearDown() override
    {
        if (runtime_h.ref) runtime_h.destroy(runtime_h.ref);
        if (ecs_h.ref) ecs_h.destroy(ecs_h.ref);
        if (scheduler_h.ref) scheduler_h.destroy(scheduler_h.ref);
    }
};

TEST_F(RuntimeSpike, Create_Tick_Destroy_NoSystems)
{
    EXPECT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
}

TEST_F(RuntimeSpike, RegisterModule_Calls_OnLoad_Once)
{
    ModuleCtx ctx;
    ke_runtime_module_params mod{};
    mod.name      = "TestModule";
    mod.user_data = &ctx;
    mod.on_load   = test_module_on_load;

    ke_module_id mid = 0;
    mid = runtime->register_module(runtime, &mod, NULL); ASSERT_NE(mid, 0u);
    EXPECT_NE(mid, 0u);
    EXPECT_EQ(ctx.load_calls.load(), 1);
}

TEST_F(RuntimeSpike, RegisteredSystem_FiresOncePerTick)
{
    ModuleCtx ctx;
    ke_runtime_module_params mod{};
    mod.name      = "TickModule";
    mod.user_data = &ctx;
    mod.on_load   = test_module_on_load;

    ke_module_id r_mid = runtime->register_module(runtime, &mod, NULL); ASSERT_NE(r_mid, 0u);

    for (int i = 0; i < 10; ++i) {
        ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    }

    EXPECT_EQ(ctx.system_ticks.load(), 10);
}

TEST_F(RuntimeSpike, RegisterModule_NullParams_Rejected)
{
    EXPECT_EQ(runtime->register_module(runtime, nullptr, NULL), (ke_module_id)0);
}

TEST_F(RuntimeSpike, RegisterSystem_NullExecute_Rejected)
{
    ke_runtime_system_params sys{};
    sys.name  = "Bad";
    sys.phase = KE_PHASE_UPDATE;
    EXPECT_EQ(runtime->register_system(runtime, &sys, nullptr), (ke_system_id)0);
}

TEST_F(RuntimeSpike, Create_RejectsNullEcs)
{
    ke_runtime_params rt_params{};
    ke_runtime_handle rt{};
    rt = ke_runtime_create(nullptr, scheduler, &rt_params, NULL);
    EXPECT_EQ(rt.ref, nullptr);
}

TEST_F(RuntimeSpike, Create_RejectsNullTaskScheduler)
{
    ke_runtime_params rt_params{};
    ke_runtime_handle rt{};
    rt = ke_runtime_create(ecs, nullptr, &rt_params, NULL);
    EXPECT_EQ(rt.ref, nullptr);
}

namespace {
struct ParallelProbe {
    std::mutex             mu;
    std::set<std::thread::id> thread_ids;
    std::atomic<int>          total_calls{0};
};
}

TEST_F(RuntimeSpike, ParallelDispatch_DisjointSystemsRunOnMultipleThreads)
{
    ParallelProbe probe;

    ke_component_access acc_a[] = {{1u, KE_ACCESS_WRITE}};
    ke_component_access acc_b[] = {{2u, KE_ACCESS_WRITE}};

    auto worker = [](ke_system_ctx *, void *ud, float) {
        auto *p = static_cast<ParallelProbe *>(ud);
        auto start = std::chrono::steady_clock::now();
        while (std::chrono::steady_clock::now() - start < std::chrono::milliseconds(5)) {  }
        {
            std::lock_guard<std::mutex> lk(p->mu);
            p->thread_ids.insert(std::this_thread::get_id());
        }
        p->total_calls.fetch_add(1);
    };

    ke_runtime_system_params sa{};
    sa.name         = "SysA";
    sa.phase        = KE_PHASE_UPDATE;
    sa.access_list  = acc_a;
    sa.access_count = 1;
    sa.user_data    = &probe;
    sa.execute      = worker;
    ASSERT_NE(runtime->register_system(runtime, &sa, nullptr), (ke_system_id)0);

    ke_runtime_system_params sb{};
    sb.name         = "SysB";
    sb.phase        = KE_PHASE_UPDATE;
    sb.access_list  = acc_b;
    sb.access_count = 1;
    sb.user_data    = &probe;
    sb.execute      = worker;
    ASSERT_NE(runtime->register_system(runtime, &sb, nullptr), (ke_system_id)0);

    for (int i = 0; i < 20; ++i)
        ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_EQ(probe.total_calls.load(), 40);
    EXPECT_GE(probe.thread_ids.size(), 2u)
        << "Expected at least 2 distinct worker threads; saw "
        << probe.thread_ids.size();
}

TEST_F(RuntimeSpike, ParallelDispatch_ConflictingSystemsSerialized)
{
    std::vector<int> order;
    std::mutex       mu;

    ke_component_access acc[] = {{42u, KE_ACCESS_WRITE}};

    auto make_tagger = [](ke_runtime_system_params &s, const char *name, int tag,
                           std::vector<int> *out_order, std::mutex *out_mu,
                           ke_component_access *acc_list)
    {
        s.name         = name;
        s.phase        = KE_PHASE_UPDATE;
        s.access_list  = acc_list;
        s.access_count = 1;
        static thread_local int                                 g_tag;
        static thread_local std::vector<int> *                   g_order;
        static thread_local std::mutex *                          g_mu;
        g_tag   = tag;
        g_order = out_order;
        g_mu    = out_mu;
    };

    struct Tagger { std::vector<int> *order; std::mutex *mu; int tag; };
    Tagger tag1{&order, &mu, 1};
    Tagger tag2{&order, &mu, 2};

    auto record = [](ke_system_ctx *, void *ud, float) {
        auto *t = static_cast<Tagger *>(ud);
        std::lock_guard<std::mutex> lk(*t->mu);
        t->order->push_back(t->tag);
    };

    (void)make_tagger;

    ke_runtime_system_params s1{};
    s1.name = "Writer1"; s1.phase = KE_PHASE_UPDATE; s1.access_list = acc; s1.access_count = 1;
    s1.user_data = &tag1; s1.execute = record;
    ASSERT_NE(runtime->register_system(runtime, &s1, nullptr), (ke_system_id)0);

    ke_runtime_system_params s2{};
    s2.name = "Writer2"; s2.phase = KE_PHASE_UPDATE; s2.access_list = acc; s2.access_count = 1;
    s2.user_data = &tag2; s2.execute = record;
    ASSERT_NE(runtime->register_system(runtime, &s2, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    ASSERT_EQ(order.size(), 2u);
    EXPECT_EQ(order[0], 1);
    EXPECT_EQ(order[1], 2);
}

TEST_F(RuntimeSpike, FixedUpdate_AccumulatesAtFixedRate)
{
    std::atomic<int> fixed_ticks{0};
    std::atomic<int> update_ticks{0};

    ke_runtime_system_params fx{};
    fx.name    = "FixedCounter";
    fx.phase   = KE_PHASE_FIXED_UPDATE;
    fx.user_data = &fixed_ticks;
    fx.execute = [](ke_system_ctx *, void *ud, float) {
        static_cast<std::atomic<int> *>(ud)->fetch_add(1);
    };
    ASSERT_NE(runtime->register_system(runtime, &fx, nullptr), (ke_system_id)0);

    ke_runtime_system_params up{};
    up.name    = "UpdateCounter";
    up.phase   = KE_PHASE_UPDATE;
    up.user_data = &update_ticks;
    up.execute = [](ke_system_ctx *, void *ud, float) {
        static_cast<std::atomic<int> *>(ud)->fetch_add(1);
    };
    ASSERT_NE(runtime->register_system(runtime, &up, nullptr), (ke_system_id)0);

    for (int i = 0; i < 10; ++i)
        ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_EQ(update_ticks.load(), 10);
    EXPECT_EQ(fixed_ticks.load(), 10);
}

TEST_F(RuntimeSpike, FixedUpdate_LargeFrame_CatchesUp)
{
    std::atomic<int> fixed_ticks{0};
    ke_runtime_system_params fx{};
    fx.name    = "FixedCounter";
    fx.phase   = KE_PHASE_FIXED_UPDATE;
    fx.user_data = &fixed_ticks;
    fx.execute = [](ke_system_ctx *, void *ud, float) {
        static_cast<std::atomic<int> *>(ud)->fetch_add(1);
    };
    ASSERT_NE(runtime->register_system(runtime, &fx, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 5.0f / 60.0f, NULL));
    EXPECT_EQ(fixed_ticks.load(), 5);
}

TEST_F(RuntimeSpike, FixedUpdate_SmallFrame_NoStep)
{
    std::atomic<int> fixed_ticks{0};
    ke_runtime_system_params fx{};
    fx.name    = "FixedCounter";
    fx.phase   = KE_PHASE_FIXED_UPDATE;
    fx.user_data = &fixed_ticks;
    fx.execute = [](ke_system_ctx *, void *ud, float) {
        static_cast<std::atomic<int> *>(ud)->fetch_add(1);
    };
    ASSERT_NE(runtime->register_system(runtime, &fx, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 120.0f, NULL));
    EXPECT_EQ(fixed_ticks.load(), 0);
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 120.0f, NULL));
    EXPECT_EQ(fixed_ticks.load(), 1);
}

TEST_F(RuntimeSpike, FixedUpdate_SpiralOfDeathGuarded)
{
    std::atomic<int> fixed_ticks{0};
    ke_runtime_system_params fx{};
    fx.name    = "FixedCounter";
    fx.phase   = KE_PHASE_FIXED_UPDATE;
    fx.user_data = &fixed_ticks;
    fx.execute = [](ke_system_ctx *, void *ud, float) {
        static_cast<std::atomic<int> *>(ud)->fetch_add(1);
    };
    ASSERT_NE(runtime->register_system(runtime, &fx, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f, NULL));
    EXPECT_LE(fixed_ticks.load(), 15);
    EXPECT_GE(fixed_ticks.load(), 14);
}

TEST_F(RuntimeSpike, Tick_RejectsNegativeDt)
{
    EXPECT_FALSE(runtime->tick(runtime, -1.0f, NULL));
}

namespace {
std::atomic<int>  g_gated_render_runs{0};
std::atomic<bool> g_gated_render_may_finish{false};

void gated_render_body(ke_system_ctx *, void *, float)
{
    while (!g_gated_render_may_finish.load()) std::this_thread::yield();
    g_gated_render_runs.fetch_add(1);
}
}

TEST_F(RuntimeSpike, Tick_DispatchesRenderAsynchronously_DoesNotBlock)
{
    g_gated_render_runs.store(0);
    g_gated_render_may_finish.store(false);

    ke_runtime_system_params rnd{};
    rnd.name = "GatedRender"; rnd.phase = KE_PHASE_RENDER;
    rnd.execute = gated_render_body;
    ASSERT_NE(runtime->register_system(runtime, &rnd, nullptr), 0u);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    EXPECT_EQ(g_gated_render_runs.load(), 0)
        << "render must not have run yet — tick() must not block on the render phase";

    g_gated_render_may_finish.store(true);
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    EXPECT_GE(g_gated_render_runs.load(), 1)
        << "the second tick's join must wait for the first tick's render to finish";
}

namespace {
template <typename Pred>
bool wait_for(Pred pred, int timeout_ms = 2000)
{
    auto start = std::chrono::steady_clock::now();
    while (!pred())
    {
        if (std::chrono::steady_clock::now() - start > std::chrono::milliseconds(timeout_ms))
            return false;
        std::this_thread::yield();
    }
    return true;
}

struct ExtractProbe
{
    ke_entity            e{};
    ke_component_id      cid{};
    std::atomic<int>     seen{-1};
    std::atomic<const void *> seen_ptr{nullptr};
    std::atomic<int>     runs{0};
};
ExtractProbe g_extract_probe;
}

TEST_F(RuntimeSpike, RenderExtract_ReflectsThisTicksSimWrite)
{
    ke_component_id cid = ecs->component_register(ecs, "Extract.Value", sizeof(int), nullptr);
    ke_entity e = ecs->entity_create(ecs);
    int *v = static_cast<int *>(ecs->component_add(ecs, e, cid));
    ASSERT_NE(v, nullptr);
    *v = 0;
    g_extract_probe.e = e;
    g_extract_probe.cid = cid;
    g_extract_probe.seen.store(-1);
    g_extract_probe.seen_ptr.store(nullptr);
    g_extract_probe.runs.store(0);

    ke_query_decl wq{}; wq.terms[0] = {cid, KE_ACCESS_WRITE}; wq.term_count = 1;
    ke_runtime_system_params sim{};
    sim.name = "SimWriter"; sim.phase = KE_PHASE_UPDATE;
    sim.queries = &wq; sim.query_count = 1;
    sim.execute = [](ke_system_ctx *ctx, void *, float) {
        size_t segc = 0;
        const ke_ecs_segment *segs = ke_system_ctx_view(ctx, 0, &segc);
        for (size_t s = 0; s < segc; s++)
        {
            int *col = static_cast<int *>(segs[s].columns[0]);
            for (size_t i = 0; i < segs[s].count; i++) col[i] = 42;
        }
    };
    ASSERT_NE(runtime->register_system(runtime, &sim, nullptr), 0u);

    ke_query_decl rq{}; rq.terms[0] = {cid, KE_ACCESS_READ}; rq.term_count = 1;
    ke_runtime_system_params rnd{};
    rnd.name = "RenderReader"; rnd.phase = KE_PHASE_RENDER;
    rnd.queries = &rq; rnd.query_count = 1;
    rnd.execute = [](ke_system_ctx *ctx, void *, float) {
        size_t segc = 0;
        const ke_ecs_segment *segs = ke_system_ctx_view(ctx, 0, &segc);
        if (segc > 0 && segs[0].count > 0)
        {
            g_extract_probe.seen.store(static_cast<const int *>(segs[0].columns[0])[0]);
            g_extract_probe.seen_ptr.store(segs[0].columns[0]);
        }
        g_extract_probe.runs.fetch_add(1);
    };
    ASSERT_NE(runtime->register_system(runtime, &rnd, nullptr), 0u);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    ASSERT_TRUE(wait_for([] { return g_extract_probe.runs.load() >= 1; }))
        << "render system never ran";

    EXPECT_EQ(g_extract_probe.seen.load(), 42) << "the extract must hand render this tick's sim write";

    const void *live_ptr = ecs->component_get(ecs, e, cid);
    EXPECT_NE(g_extract_probe.seen_ptr.load(), live_ptr)
        << "render must read an owned copy, never the live component storage";
}

namespace {
struct MultiTermExtract { float x, y, z; };
double g_extract_pv_sum = 0.0;
std::atomic<int> g_extract_pv_runs{0};
}

TEST_F(RuntimeSpike, RenderExtract_MultiTermAlignment)
{
    ke_component_id pos = ecs->component_register(ecs, "ExtractPos", sizeof(MultiTermExtract), nullptr);
    ke_component_id vel = ecs->component_register(ecs, "ExtractVel", sizeof(MultiTermExtract), nullptr);

    double expect = 0.0;
    for (int i = 0; i < 64; i++)
    {
        ke_entity e = ecs->entity_create(ecs);
        ecs->component_add(ecs, e, pos);
        ecs->component_add(ecs, e, vel);
        auto *p = static_cast<MultiTermExtract *>(ecs->component_get(ecs, e, pos));
        auto *v = static_cast<MultiTermExtract *>(ecs->component_get(ecs, e, vel));
        ASSERT_NE(p, nullptr);
        ASSERT_NE(v, nullptr);
        p->x = static_cast<float>(i);
        v->x = static_cast<float>(i * 2);
        expect += static_cast<double>(i) + static_cast<double>(i * 2);
    }

    ke_query_decl rq{};
    rq.terms[0] = {pos, KE_ACCESS_READ};
    rq.terms[1] = {vel, KE_ACCESS_READ};
    rq.term_count = 2;
    ke_runtime_system_params rnd{};
    rnd.name = "RenderPosVel"; rnd.phase = KE_PHASE_RENDER;
    rnd.queries = &rq; rnd.query_count = 1;
    rnd.execute = [](ke_system_ctx *ctx, void *, float) {
        size_t segc = 0;
        const ke_ecs_segment *segs = ke_system_ctx_view(ctx, 0, &segc);
        for (size_t s = 0; s < segc; s++)
        {
            const auto *pc = static_cast<const MultiTermExtract *>(segs[s].columns[0]);
            const auto *vc = static_cast<const MultiTermExtract *>(segs[s].columns[1]);
            for (size_t i = 0; i < segs[s].count; i++)
                g_extract_pv_sum += static_cast<double>(pc[i].x) + static_cast<double>(vc[i].x);
        }
        g_extract_pv_runs.fetch_add(1);
    };
    ASSERT_NE(runtime->register_system(runtime, &rnd, nullptr), 0u);

    g_extract_pv_sum = 0.0;
    g_extract_pv_runs.store(0);
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    ASSERT_TRUE(wait_for([] { return g_extract_pv_runs.load() >= 1; }))
        << "render system never ran";
    EXPECT_DOUBLE_EQ(g_extract_pv_sum, expect)
        << "the extract's merge-copy must preserve per-entity column alignment";
}

namespace wave_test {

ke_runtime_system_params make_system(const ke_component_access *list, uint32_t count)
{
    ke_runtime_system_params s{};
    s.name         = "Synthetic";
    s.phase        = KE_PHASE_UPDATE;
    s.access_list  = list;
    s.access_count = count;
    s.execute      = [](ke_system_ctx *, void *, float) {};
    return s;
}

}

TEST(WaveBuilder, Empty_NoWaves)
{
    uint32_t assignments[4] = {99, 99, 99, 99};
    uint32_t wave_count = 99;
    ke_runtime_debug_compute_waves(nullptr, 0, assignments, &wave_count);
    EXPECT_EQ(wave_count, 0u);
}

TEST(WaveBuilder, SingleSystem_OneWave)
{
    ke_component_access acc[] = {{1u, KE_ACCESS_WRITE}};
    auto s = wave_test::make_system(acc, 1);

    uint32_t assignments[1] = {99};
    uint32_t wave_count = 0;
    ke_runtime_debug_compute_waves(&s, 1, assignments, &wave_count);

    EXPECT_EQ(wave_count, 1u);
    EXPECT_EQ(assignments[0], 0u);
}

TEST(WaveBuilder, DisjointWrites_SameWave)
{
    ke_component_access a[] = {{1u, KE_ACCESS_WRITE}};
    ke_component_access b[] = {{2u, KE_ACCESS_WRITE}};
    ke_runtime_system_params sys[] = {
        wave_test::make_system(a, 1),
        wave_test::make_system(b, 1),
    };

    uint32_t assignments[2] = {99, 99};
    uint32_t wave_count = 0;
    ke_runtime_debug_compute_waves(sys, 2, assignments, &wave_count);

    EXPECT_EQ(wave_count, 1u);
    EXPECT_EQ(assignments[0], 0u);
    EXPECT_EQ(assignments[1], 0u);
}

TEST(WaveBuilder, WriteWriteSameCid_DistinctWaves)
{
    ke_component_access a[] = {{1u, KE_ACCESS_WRITE}};
    ke_component_access b[] = {{1u, KE_ACCESS_WRITE}};
    ke_runtime_system_params sys[] = {
        wave_test::make_system(a, 1),
        wave_test::make_system(b, 1),
    };

    uint32_t assignments[2] = {99, 99};
    uint32_t wave_count = 0;
    ke_runtime_debug_compute_waves(sys, 2, assignments, &wave_count);

    EXPECT_EQ(wave_count, 2u);
    EXPECT_EQ(assignments[0], 0u);
    EXPECT_EQ(assignments[1], 1u);
}

TEST(WaveBuilder, WriteReadSameCid_DistinctWaves)
{
    ke_component_access a[] = {{5u, KE_ACCESS_WRITE}};
    ke_component_access b[] = {{5u, KE_ACCESS_READ}};
    ke_runtime_system_params sys[] = {
        wave_test::make_system(a, 1),
        wave_test::make_system(b, 1),
    };

    uint32_t assignments[2] = {99, 99};
    uint32_t wave_count = 0;
    ke_runtime_debug_compute_waves(sys, 2, assignments, &wave_count);

    EXPECT_EQ(wave_count, 2u);
}

TEST(WaveBuilder, ReadReadSameCid_SameWave)
{
    ke_component_access a[] = {{7u, KE_ACCESS_READ}};
    ke_component_access b[] = {{7u, KE_ACCESS_READ}};
    ke_runtime_system_params sys[] = {
        wave_test::make_system(a, 1),
        wave_test::make_system(b, 1),
    };

    uint32_t assignments[2] = {99, 99};
    uint32_t wave_count = 0;
    ke_runtime_debug_compute_waves(sys, 2, assignments, &wave_count);

    EXPECT_EQ(wave_count, 1u);
    EXPECT_EQ(assignments[0], 0u);
    EXPECT_EQ(assignments[1], 0u);
}

TEST(WaveBuilder, ChainOfConflicts_GreedyGrouping)
{
    ke_component_access a[] = {{1u, KE_ACCESS_WRITE}};
    ke_component_access b[] = {{1u, KE_ACCESS_READ}};
    ke_component_access c[] = {{2u, KE_ACCESS_WRITE}};
    ke_component_access d[] = {{2u, KE_ACCESS_READ}};
    ke_runtime_system_params sys[] = {
        wave_test::make_system(a, 1),
        wave_test::make_system(b, 1),
        wave_test::make_system(c, 1),
        wave_test::make_system(d, 1),
    };

    uint32_t assignments[4] = {99, 99, 99, 99};
    uint32_t wave_count = 0;
    ke_runtime_debug_compute_waves(sys, 4, assignments, &wave_count);

    EXPECT_EQ(wave_count, 3u);
    EXPECT_EQ(assignments[0], 0u);
    EXPECT_EQ(assignments[1], 1u);
    EXPECT_EQ(assignments[2], 1u);
    EXPECT_EQ(assignments[3], 2u);
}

TEST(WaveBuilder, ClearShadowCull_RealAccessShape_SameWave)
{
    ke_component_access clear[]  = {{1u, KE_ACCESS_READ}, {2u, KE_ACCESS_WRITE}};
    ke_component_access shadow[] = {{1u, KE_ACCESS_READ}, {3u, KE_ACCESS_READ}, {4u, KE_ACCESS_WRITE}};
    ke_component_access cull[]   = {{1u, KE_ACCESS_READ}, {3u, KE_ACCESS_READ}, {5u, KE_ACCESS_WRITE}};
    ke_runtime_system_params sys[] = {
        wave_test::make_system(clear, 2),
        wave_test::make_system(shadow, 3),
        wave_test::make_system(cull, 3),
    };

    uint32_t assignments[3] = {99, 99, 99};
    uint32_t wave_count = 0;
    ke_runtime_debug_compute_waves(sys, 3, assignments, &wave_count);

    EXPECT_EQ(wave_count, 1u) << "clear+shadow+cull's real access shape must land in one wave";
    EXPECT_EQ(assignments[0], assignments[1]);
    EXPECT_EQ(assignments[1], assignments[2]);
}

TEST_F(RuntimeSpike, DeferSpawn_AppliedAtWaveBarrier)
{
    ke_system_ctx_reset_defer_applied();

    int spawn_calls = 0;
    ke_runtime_system_params sys{};
    sys.name      = "Spawner";
    sys.phase     = KE_PHASE_UPDATE;
    sys.user_data = &spawn_calls;
    sys.execute   = [](ke_system_ctx *ctx, void *ud, float) {
        auto *count = static_cast<int *>(ud);
        ke_system_ctx_spawn(ctx);
        ke_system_ctx_spawn(ctx);
        ke_system_ctx_spawn(ctx);
        (*count)++;
    };
    ASSERT_NE(runtime->register_system(runtime, &sys, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    EXPECT_EQ(spawn_calls, 1);
    EXPECT_EQ(ke_system_ctx_defer_applied_count(), 3u);
}

TEST_F(RuntimeSpike, DeferAttachDetachDespawn_AppliedAtBarrier)
{
    ke_system_ctx_reset_defer_applied();

    char payload = 'X';
    ke_runtime_system_params sys{};
    sys.name      = "Mutator";
    sys.phase     = KE_PHASE_UPDATE;
    sys.user_data = &payload;
    sys.execute   = [](ke_system_ctx *ctx, void *ud, float) {
        EXPECT_TRUE(ke_system_ctx_attach(ctx, 42u, 5u, ud, 1));
        EXPECT_TRUE(ke_system_ctx_detach(ctx, 42u, 5u));
        EXPECT_TRUE(ke_system_ctx_despawn(ctx, 42u));
    };
    ASSERT_NE(runtime->register_system(runtime, &sys, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    EXPECT_EQ(ke_system_ctx_defer_applied_count(), 3u);
}

TEST_F(RuntimeSpike, DeferQueue_DrainsBetweenTicks)
{
    ke_system_ctx_reset_defer_applied();

    ke_runtime_system_params sys{};
    sys.name      = "RepeatSpawner";
    sys.phase     = KE_PHASE_UPDATE;
    sys.execute   = [](ke_system_ctx *ctx, void *, float) {
        ke_entity e = ke_system_ctx_spawn(ctx);
        (void)e;
    };
    ASSERT_NE(runtime->register_system(runtime, &sys, nullptr), (ke_system_id)0);

    for (int i = 0; i < 5; ++i)
        ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_EQ(ke_system_ctx_defer_applied_count(), 5u);
}

TEST(FlecsTagTest, ZeroSizeComponent_RegistersAsUsableTag)
{
    ke_ecs_flecs_params p{};
    ke_ecs_handle h{};
    h = ke_ecs_flecs_create(&p, nullptr); ASSERT_NE(h.ref, nullptr);

    ke_component_id tag = h.ref->component_register(h.ref, "ZeroSizeTag", 0, nullptr);
    EXPECT_NE(tag, (ke_component_id)0) << "zero-size component should be a valid tag";

    ke_entity e = h.ref->entity_create(h.ref);
    h.ref->component_add(h.ref, e, tag);

    ke_query_id q = h.ref->query_register(h.ref, &tag, 1);
    ASSERT_NE(q, KE_QUERY_INVALID) << "a tag must be registrable as a query term";

    ke_ecs_segment segs[8]{};
    size_t         seg_count = 0;
    h.ref->query_resolve(h.ref, q, segs, 8, &seg_count);

    size_t total = 0;
    for (size_t i = 0; i < seg_count; i++) total += segs[i].count;
    EXPECT_EQ(total, (size_t)1) << "entity carrying the tag should be found";

    h.destroy(h.ref);
}


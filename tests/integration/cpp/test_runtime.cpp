#include <gtest/gtest.h>

#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>

#include <atomic>
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

}  // namespace

// RuntimeSpike covers the split runtime + ECS plugin pair:
// - ke_ecs_flecs_create() builds the storage (flecs world behind ke_ecs).
// - ke_runtime_create(ecs) builds the scheduler (in-house, sequential for now, NULL, NULL).
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
    // sys.execute deliberately null
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

// ── Parallel execution via enki dispatcher ──────────────────────────────────

namespace {
struct ParallelProbe {
    std::mutex             mu;
    std::set<std::thread::id> thread_ids;
    std::atomic<int>          total_calls{0};
};
}

TEST_F(RuntimeSpike, ParallelDispatch_DisjointSystemsRunOnMultipleThreads)
{
    // Two systems with completely disjoint access — same wave by the wave
    // builder, so enki dispatches them concurrently. Each records the thread
    // id it ran on; the union over many ticks should span multiple workers.
    ParallelProbe probe;

    ke_component_access acc_a[] = {{1u, KE_ACCESS_WRITE}};
    ke_component_access acc_b[] = {{2u, KE_ACCESS_WRITE}};

    auto worker = [](ke_system_ctx *, void *ud, float) {
        auto *p = static_cast<ParallelProbe *>(ud);
        // A small busy-wait so the two systems overlap in real time. Pure
        // dispatch without overlap could land on the same worker even with
        // multiple threads available.
        auto start = std::chrono::steady_clock::now();
        while (std::chrono::steady_clock::now() - start < std::chrono::milliseconds(5)) { /* spin */ }
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

    // 20 ticks * 2 systems = 40 calls. Across these we should observe at
    // least 2 distinct worker thread ids if dispatch is genuinely parallel.
    for (int i = 0; i < 20; ++i)
        ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_EQ(probe.total_calls.load(), 40);
    EXPECT_GE(probe.thread_ids.size(), 2u)
        << "Expected at least 2 distinct worker threads; saw "
        << probe.thread_ids.size();
}

TEST_F(RuntimeSpike, ParallelDispatch_ConflictingSystemsSerialized)
{
    // Two systems writing the same component — wave builder splits them into
    // separate waves, so they run sequentially. Verify execution_order rather
    // than thread parallelism.
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

    // Use struct-bound state instead of thread_local trickery.
    struct Tagger { std::vector<int> *order; std::mutex *mu; int tag; };
    Tagger tag1{&order, &mu, 1};
    Tagger tag2{&order, &mu, 2};

    auto record = [](ke_system_ctx *, void *ud, float) {
        auto *t = static_cast<Tagger *>(ud);
        std::lock_guard<std::mutex> lk(*t->mu);
        t->order->push_back(t->tag);
    };

    (void)make_tagger;  // suppress unused capture helper

    ke_runtime_system_params s1{};
    s1.name = "Writer1"; s1.phase = KE_PHASE_UPDATE; s1.access_list = acc; s1.access_count = 1;
    s1.user_data = &tag1; s1.execute = record;
    ASSERT_NE(runtime->register_system(runtime, &s1, nullptr), (ke_system_id)0);

    ke_runtime_system_params s2{};
    s2.name = "Writer2"; s2.phase = KE_PHASE_UPDATE; s2.access_list = acc; s2.access_count = 1;
    s2.user_data = &tag2; s2.execute = record;
    ASSERT_NE(runtime->register_system(runtime, &s2, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    // Wave builder ensures Writer1 (wave 0) completes before Writer2 (wave 1)
    // starts — defer flush sits between them. So order MUST be [1, 2].
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

    // Default fixed_dt = 1/60. Tick at 1/60 ten times: each tick contributes
    // exactly one fixed step.
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

    // Default fixed_dt = 1/60. One tick of 5/60s feeds 5 fixed steps.
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

    // Tick at 1/120 → below fixed_dt threshold. After one tick, accumulator
    // holds (1/120) and no fixed step fires. Two ticks brings accumulator to
    // 2/120 = 1/60 → one fixed step fires.
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

    // Default max accum = 0.25s = 15 fixed steps at 1/60. A 1.0s pause must
    // be capped: fixed_ticks should NOT be 60.
    ASSERT_TRUE(runtime->tick(runtime, 1.0f, NULL));
    EXPECT_LE(fixed_ticks.load(), 15);
    EXPECT_GE(fixed_ticks.load(), 14);  // floor(0.25 / (1/60))
}

TEST_F(RuntimeSpike, Tick_RejectsNegativeDt)
{
    EXPECT_FALSE(runtime->tick(runtime, -1.0f, NULL));
}

// ── Debug access checks ─────────────────────────────────────────────────────

TEST_F(RuntimeSpike, DebugCheck_FiresWhenSystemMutatesUndeclaredComponent)
{
    ke_system_ctx_reset_check_failures();

    // Register a system that declares NO access, tries to mutate component 7.
    ke_runtime_system_params sys{};
    sys.name    = "Misbehaving";
    sys.phase   = KE_PHASE_UPDATE;
    sys.execute = [](ke_system_ctx *ctx, void *, float) {
        void *p = ke_system_ctx_get_mut(ctx, 7u, 1u);
        EXPECT_EQ(p, nullptr);  // check denied + returned NULL
    };
    ASSERT_NE(runtime->register_system(runtime, &sys, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_GE(ke_system_ctx_check_failures(), 1u);
}

TEST_F(RuntimeSpike, DebugCheck_PassesWhenAccessDeclared)
{
    ke_system_ctx_reset_check_failures();

    ke_component_access access[] = {{7u, KE_ACCESS_WRITE}};
    ke_runtime_system_params sys{};
    sys.name         = "Declared";
    sys.phase        = KE_PHASE_UPDATE;
    sys.access_list  = access;
    sys.access_count = 1;
    sys.execute = [](ke_system_ctx *ctx, void *, float) {
        // Storage stubs in the prototype: get_mut may return NULL because
        // ke_ecs_flecs doesn't actually carry component 7 — what we care about
        // here is that the DEBUG CHECK doesn't fire (no failure recorded).
        (void)ke_system_ctx_get_mut(ctx, 7u, 1u);
    };
    ASSERT_NE(runtime->register_system(runtime, &sys, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_EQ(ke_system_ctx_check_failures(), 0u);
}

TEST_F(RuntimeSpike, DebugCheck_ExclusiveBypassesValidation)
{
    ke_system_ctx_reset_check_failures();

    ke_runtime_system_params sys{};
    sys.name      = "Exclusive";
    sys.phase     = KE_PHASE_UPDATE;
    sys.exclusive = true;  // bypass — opaque code path
    sys.execute = [](ke_system_ctx *ctx, void *, float) {
        // Even with no access_list, exclusive systems get through.
        (void)ke_system_ctx_get_mut(ctx, 7u, 1u);
        (void)ke_system_ctx_get(ctx, 8u, 2u);
    };
    ASSERT_NE(runtime->register_system(runtime, &sys, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_EQ(ke_system_ctx_check_failures(), 0u);
}

// ── §16 sim/render component snapshot ────────────────────────────────────────

TEST_F(RuntimeSpike, Snapshot_FreezesLiveSide)
{
    ke_component_id cid = ecs->component_register_v3(ecs, "Snap.Probe", sizeof(int),
                                                     KE_COMPONENT_DOUBLE_BUFFERED);
    ASSERT_NE(cid, 0u);
    ke_component_id snap = ecs->snapshot_cid(ecs, cid);
    EXPECT_NE(snap, cid);  // double-buffered → distinct snapshot cid

    ke_entity e = ecs->entity_create(ecs);
    int *live = static_cast<int *>(ecs->component_add(ecs, e, cid));
    ASSERT_NE(live, nullptr);
    *live = 100;

    ecs->swap_snapshots(ecs);  // freeze live(100) → snapshot

    int *snap_ptr = static_cast<int *>(ecs->component_get(ecs, e, snap));
    ASSERT_NE(snap_ptr, nullptr);
    EXPECT_EQ(*snap_ptr, 100);

    // Mutate live WITHOUT swapping — the snapshot must stay frozen. This is the
    // property that lets render N read a stable view while sim writes on.
    static_cast<int *>(ecs->component_get(ecs, e, cid))[0] = 200;
    EXPECT_EQ(static_cast<int *>(ecs->component_get(ecs, e, snap))[0], 100);
    EXPECT_EQ(static_cast<int *>(ecs->component_get(ecs, e, cid))[0], 200);
}

TEST_F(RuntimeSpike, Snapshot_SingleBuffered_IsIdentity)
{
    ke_component_id cid = ecs->component_register(ecs, "Snap.Single", sizeof(int));
    EXPECT_EQ(ecs->snapshot_cid(ecs, cid), cid);  // not double-buffered → identity
}

namespace {
struct SnapE2E { ke_entity e; ke_component_id cid; int seen; };
SnapE2E g_snap_e2e;
}

TEST_F(RuntimeSpike, SimWrites_RenderReadsSnapshot)
{
    ke_component_id cid = ecs->component_register(ecs, "E2E.Value", sizeof(int));
    ke_entity e = ecs->entity_create(ecs);
    int *v = static_cast<int *>(ecs->component_add(ecs, e, cid));
    ASSERT_NE(v, nullptr);
    *v = 0;
    g_snap_e2e = { e, cid, -1 };

    // Sim system (UPDATE): writes the live side = 42.
    ke_component_access wacc[] = {{cid, KE_ACCESS_WRITE}};
    ke_runtime_system_params sim{};
    sim.name = "SimWriter"; sim.phase = KE_PHASE_UPDATE;
    sim.access_list = wacc; sim.access_count = 1;
    sim.execute = [](ke_system_ctx *ctx, void *, float) {
        int *p = static_cast<int *>(ke_system_ctx_get_mut(ctx, g_snap_e2e.cid, g_snap_e2e.e));
        if (p) *p = 42;
    };
    ASSERT_NE(runtime->register_system(runtime, &sim, nullptr), 0u);

    // Render system (RENDER): reads cid — routed to the snapshot side.
    ke_component_access racc[] = {{cid, KE_ACCESS_READ}};
    ke_runtime_system_params rnd{};
    rnd.name = "RenderReader"; rnd.phase = KE_PHASE_RENDER;
    rnd.access_list = racc; rnd.access_count = 1;
    rnd.execute = [](ke_system_ctx *ctx, void *, float) {
        const int *p = static_cast<const int *>(ke_system_ctx_get(ctx, g_snap_e2e.cid, g_snap_e2e.e));
        g_snap_e2e.seen = p ? *p : -999;
    };
    ASSERT_NE(runtime->register_system(runtime, &rnd, nullptr), 0u);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    // Inference double-buffered cid (a render system reads it); the swap froze
    // sim's just-written 42 into the snapshot the render system read.
    EXPECT_NE(ecs->snapshot_cid(ecs, cid), cid);
    EXPECT_EQ(g_snap_e2e.seen, 42);
}

// ── Wave builder (R/W conflict grouping) ────────────────────────────────────
//
// These tests don't need the RuntimeSpike fixture — they exercise the pure
// wave builder function directly. Easier to isolate algorithmic correctness
// from runtime state.

namespace wave_test {

ke_runtime_system_params make_system(const ke_component_access *list, uint32_t count, bool exclusive = false)
{
    ke_runtime_system_params s{};
    s.name         = "Synthetic";
    s.phase        = KE_PHASE_UPDATE;
    s.access_list  = list;
    s.access_count = count;
    s.exclusive    = exclusive;
    s.execute      = [](ke_system_ctx *, void *, float) {};
    return s;
}

}  // namespace wave_test

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

TEST(WaveBuilder, ExclusiveSystem_AlwaysAlone)
{
    // Three systems, none conflict. Middle one is exclusive → forces split.
    ke_component_access a[] = {{1u, KE_ACCESS_READ}};
    ke_component_access b[] = {{2u, KE_ACCESS_READ}};
    ke_component_access c[] = {{3u, KE_ACCESS_READ}};
    ke_runtime_system_params sys[] = {
        wave_test::make_system(a, 1),
        wave_test::make_system(b, 1, /*exclusive=*/true),
        wave_test::make_system(c, 1),
    };

    uint32_t assignments[3] = {99, 99, 99};
    uint32_t wave_count = 0;
    ke_runtime_debug_compute_waves(sys, 3, assignments, &wave_count);

    EXPECT_EQ(wave_count, 3u);
    EXPECT_EQ(assignments[0], 0u);
    EXPECT_EQ(assignments[1], 1u);
    EXPECT_EQ(assignments[2], 2u);
}

TEST(WaveBuilder, ChainOfConflicts_GreedyGrouping)
{
    // A writes T, B reads T → conflict. C writes U (disjoint from A, B) → can
    // join A's wave (no conflict with A). D reads U → conflicts with C, but C
    // is in wave 0 now... let's verify the actual greedy behavior.
    //
    // Registration order:
    //   sys[0] A: writes T
    //   sys[1] B: reads T   → conflicts with A → wave 1
    //   sys[2] C: writes U  → wave 1 has B (reads T), no conflict → joins wave 1
    //   sys[3] D: reads U   → conflicts with C in wave 1 → wave 2
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

// ── Defer queue ─────────────────────────────────────────────────────────────

TEST_F(RuntimeSpike, DeferSpawn_AppliedAtWaveBarrier)
{
    ke_system_ctx_reset_defer_applied();

    int spawn_calls = 0;
    ke_runtime_system_params sys{};
    sys.name      = "Spawner";
    sys.phase     = KE_PHASE_UPDATE;
    sys.exclusive = true;
    sys.user_data = &spawn_calls;
    sys.execute   = [](ke_system_ctx *ctx, void *ud, float) {
        auto *count = static_cast<int *>(ud);
        // spawn returns a placeholder (KE_ENTITY_INVALID) until the defer queue flushes
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
    sys.exclusive = true;
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
    sys.exclusive = true;
    sys.execute   = [](ke_system_ctx *ctx, void *, float) {
        ke_entity e = ke_system_ctx_spawn(ctx);
        (void)e;
    };
    ASSERT_NE(runtime->register_system(runtime, &sys, nullptr), (ke_system_id)0);

    for (int i = 0; i < 5; ++i)
        ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_EQ(ke_system_ctx_defer_applied_count(), 5u);  // exactly 1 per tick, drains every wave
}

// ── Abort interception ───────────────────────────────────────────────────────

// A zero-size component registers as a tag (entity id, no data): valid in
// add/has/query and used as a render-resource dependency key. It must register
// cleanly — not abort and not corrupt the world (a fatal here silently broke
// every later ecs op, e.g. the forward render pass's component queries).
TEST(FlecsTagTest, ZeroSizeComponent_RegistersAsUsableTag)
{
    ke_ecs_flecs_params p{};
    ke_ecs_handle h{};
    h = ke_ecs_flecs_create(&p, nullptr); ASSERT_NE(h.ref, nullptr);

    ke_component_id tag = h.ref->component_register(h.ref, "ZeroSizeTag", 0);
    EXPECT_NE(tag, (ke_component_id)0) << "zero-size component should be a valid tag";

    // The world must stay usable: add the tag + a sized component, then query.
    ke_entity e = h.ref->entity_create(h.ref);
    h.ref->component_add(h.ref, e, tag);

    ke_entity *ents = nullptr; void *data = nullptr; size_t count = 0;
    h.ref->query(h.ref, tag, &ents, &data, &count);
    EXPECT_EQ(count, (size_t)1) << "entity carrying the tag should be found";

    h.destroy(h.ref);
}

TEST_F(RuntimeSpike, DebugCheck_ReadAccessAlsoSatisfiesGetCall)
{
    ke_system_ctx_reset_check_failures();

    ke_component_access access[] = {{9u, KE_ACCESS_READ}};
    ke_runtime_system_params sys{};
    sys.name         = "Reader";
    sys.phase        = KE_PHASE_UPDATE;
    sys.access_list  = access;
    sys.access_count = 1;
    sys.execute = [](ke_system_ctx *ctx, void *, float) {
        (void)ke_system_ctx_get(ctx, 9u, 1u);    // declared READ → ok
        const void *bad = ke_system_ctx_get(ctx, 10u, 1u);  // undeclared → check fires
        EXPECT_EQ(bad, nullptr);
    };
    ASSERT_NE(runtime->register_system(runtime, &sys, nullptr), (ke_system_id)0);

    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_GE(ke_system_ctx_check_failures(), 1u);
}

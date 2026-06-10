#include <gtest/gtest.h>

#include <kernel_engine/kernel/runtime/runtime_create.h>
#include <kernel_engine/kernel/runtime/system_ctx.h>
#include <kernel_engine/kernel/world/ke_ecs.h>
#include <kernel_engine/kernel/world/ke_ecs_flecs.h>

#include <atomic>

namespace {

struct ModuleCtx {
    std::atomic<int> load_calls{0};
    std::atomic<int> system_ticks{0};
};

ke_result test_module_on_load(ke_runtime *runtime, void *user_data)
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

    ke_system_id sid = 0;
    return runtime->register_system(runtime, &sys, &sid);
}

}  // namespace

// RuntimeSpike covers the split runtime + ECS plugin pair:
// - ke_ecs_flecs_create() builds the storage (flecs world behind ke_ecs).
// - ke_runtime_create(ecs) builds the scheduler (in-house, sequential for now).
class RuntimeSpike : public ::testing::Test {
protected:
    ke_allocator *allocator = nullptr;
    ke_ecs       *ecs       = nullptr;
    ke_runtime   *runtime   = nullptr;

    void SetUp() override
    {
        allocator = ke_allocator_malloc_create();
        ASSERT_NE(allocator, nullptr);

        ke_ecs_flecs_params ecs_params{};
        ASSERT_EQ(ke_ecs_flecs_create(allocator, &ecs_params, &ecs), KE_OK);
        ASSERT_NE(ecs, nullptr);

        ke_runtime_params rt_params{};
        ASSERT_EQ(ke_runtime_create(allocator, ecs, &rt_params, &runtime), KE_OK);
        ASSERT_NE(runtime, nullptr);
    }

    void TearDown() override
    {
        if (runtime) runtime->destroy(runtime);
        if (ecs) ecs->destroy(ecs);
    }
};

TEST_F(RuntimeSpike, Create_Tick_Destroy_NoSystems)
{
    EXPECT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);
}

TEST_F(RuntimeSpike, RegisterModule_Calls_OnLoad_Once)
{
    ModuleCtx ctx;
    ke_runtime_module_params mod{};
    mod.name      = "TestModule";
    mod.user_data = &ctx;
    mod.on_load   = test_module_on_load;

    ke_module_id mid = 0;
    ASSERT_EQ(runtime->register_module(runtime, &mod, &mid), KE_OK);
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

    ASSERT_EQ(runtime->register_module(runtime, &mod, nullptr), KE_OK);

    for (int i = 0; i < 10; ++i) {
        ASSERT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);
    }

    EXPECT_EQ(ctx.system_ticks.load(), 10);
}

TEST_F(RuntimeSpike, RegisterModule_NullParams_Rejected)
{
    EXPECT_EQ(runtime->register_module(runtime, nullptr, nullptr),
              KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(RuntimeSpike, RegisterSystem_NullExecute_Rejected)
{
    ke_runtime_system_params sys{};
    sys.name  = "Bad";
    sys.phase = KE_PHASE_UPDATE;
    // sys.execute deliberately null
    EXPECT_EQ(runtime->register_system(runtime, &sys, nullptr),
              KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(RuntimeSpike, Create_RejectsNullEcs)
{
    ke_runtime_params rt_params{};
    ke_runtime *rt = nullptr;
    EXPECT_EQ(ke_runtime_create(allocator, nullptr, &rt_params, &rt),
              KE_ERROR_INVALID_ARGUMENT);
    EXPECT_EQ(rt, nullptr);
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
    ASSERT_EQ(runtime->register_system(runtime, &fx, nullptr), KE_OK);

    ke_runtime_system_params up{};
    up.name    = "UpdateCounter";
    up.phase   = KE_PHASE_UPDATE;
    up.user_data = &update_ticks;
    up.execute = [](ke_system_ctx *, void *ud, float) {
        static_cast<std::atomic<int> *>(ud)->fetch_add(1);
    };
    ASSERT_EQ(runtime->register_system(runtime, &up, nullptr), KE_OK);

    // Default fixed_dt = 1/60. Tick at 1/60 ten times: each tick contributes
    // exactly one fixed step.
    for (int i = 0; i < 10; ++i)
        ASSERT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);

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
    ASSERT_EQ(runtime->register_system(runtime, &fx, nullptr), KE_OK);

    // Default fixed_dt = 1/60. One tick of 5/60s feeds 5 fixed steps.
    ASSERT_EQ(runtime->tick(runtime, 5.0f / 60.0f), KE_OK);
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
    ASSERT_EQ(runtime->register_system(runtime, &fx, nullptr), KE_OK);

    // Tick at 1/120 → below fixed_dt threshold. After one tick, accumulator
    // holds (1/120) and no fixed step fires. Two ticks brings accumulator to
    // 2/120 = 1/60 → one fixed step fires.
    ASSERT_EQ(runtime->tick(runtime, 1.0f / 120.0f), KE_OK);
    EXPECT_EQ(fixed_ticks.load(), 0);
    ASSERT_EQ(runtime->tick(runtime, 1.0f / 120.0f), KE_OK);
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
    ASSERT_EQ(runtime->register_system(runtime, &fx, nullptr), KE_OK);

    // Default max accum = 0.25s = 15 fixed steps at 1/60. A 1.0s pause must
    // be capped: fixed_ticks should NOT be 60.
    ASSERT_EQ(runtime->tick(runtime, 1.0f), KE_OK);
    EXPECT_LE(fixed_ticks.load(), 15);
    EXPECT_GE(fixed_ticks.load(), 14);  // floor(0.25 / (1/60))
}

TEST_F(RuntimeSpike, Tick_RejectsNegativeDt)
{
    EXPECT_EQ(runtime->tick(runtime, -1.0f), KE_ERROR_INVALID_ARGUMENT);
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
    ASSERT_EQ(runtime->register_system(runtime, &sys, nullptr), KE_OK);

    ASSERT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);

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
    ASSERT_EQ(runtime->register_system(runtime, &sys, nullptr), KE_OK);

    ASSERT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);

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
    ASSERT_EQ(runtime->register_system(runtime, &sys, nullptr), KE_OK);

    ASSERT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);

    EXPECT_EQ(ke_system_ctx_check_failures(), 0u);
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
        ke_entity e1 = 0, e2 = 0, e3 = 0;
        EXPECT_EQ(ke_system_ctx_spawn(ctx, &e1), KE_OK);
        EXPECT_EQ(ke_system_ctx_spawn(ctx, &e2), KE_OK);
        EXPECT_EQ(ke_system_ctx_spawn(ctx, &e3), KE_OK);
        (*count)++;
    };
    ASSERT_EQ(runtime->register_system(runtime, &sys, nullptr), KE_OK);

    ASSERT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);
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
        EXPECT_EQ(ke_system_ctx_attach(ctx, 42u, 5u, ud, 1), KE_OK);
        EXPECT_EQ(ke_system_ctx_detach(ctx, 42u, 5u), KE_OK);
        EXPECT_EQ(ke_system_ctx_despawn(ctx, 42u), KE_OK);
    };
    ASSERT_EQ(runtime->register_system(runtime, &sys, nullptr), KE_OK);

    ASSERT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);
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
        ke_entity e = 0;
        ke_system_ctx_spawn(ctx, &e);
    };
    ASSERT_EQ(runtime->register_system(runtime, &sys, nullptr), KE_OK);

    for (int i = 0; i < 5; ++i)
        ASSERT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);

    EXPECT_EQ(ke_system_ctx_defer_applied_count(), 5u);  // exactly 1 per tick, drains every wave
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
    ASSERT_EQ(runtime->register_system(runtime, &sys, nullptr), KE_OK);

    ASSERT_EQ(runtime->tick(runtime, 1.0f / 60.0f), KE_OK);

    EXPECT_GE(ke_system_ctx_check_failures(), 1u);
}

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

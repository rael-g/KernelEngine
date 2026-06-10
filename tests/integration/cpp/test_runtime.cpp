#include <gtest/gtest.h>

#include <kernel_engine/kernel/runtime/runtime_create.h>
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

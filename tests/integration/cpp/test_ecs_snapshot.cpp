#include <gtest/gtest.h>

#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/scheduler/enki/enki_scheduler.h>

// The sim→render component snapshot: a component a render-phase system reads is
// double-buffered, the sim writes the live side, and the render phase reads a
// back buffer frozen at the phase boundary.
//
// Under serial sim→render execution the swap happens immediately before the
// render phase, so the snapshot and the live side hold the SAME value while a
// render body runs — a value comparison cannot tell the two apart. These tests
// therefore discriminate structurally (which storage the resolved view points
// at) and across the phase boundary (what the snapshot holds once the live side
// moves on), which is what actually breaks if read routing regresses.

namespace {

struct Pos
{
    float x, y, z;
};

const void *g_render_column   = nullptr;
size_t      g_render_segments = 0;
float       g_render_value    = 0.0f;

const void *g_sim_column = nullptr;

void render_reader(ke_system_ctx *ctx, void *, float)
{
    size_t                seg_count = 0;
    const ke_ecs_segment *segs      = ke_system_ctx_view(ctx, 0, &seg_count);
    g_render_segments               = seg_count;
    if (seg_count == 0) return;
    g_render_column = segs[0].columns[0];
    const Pos *col  = static_cast<const Pos *>(segs[0].columns[0]);
    if (col) g_render_value = col[0].x;
}

void sim_reader(ke_system_ctx *ctx, void *, float)
{
    size_t                seg_count = 0;
    const ke_ecs_segment *segs      = ke_system_ctx_view(ctx, 0, &seg_count);
    if (seg_count == 0) return;
    g_sim_column = segs[0].columns[0];
}

}  // namespace

class EcsSnapshot : public ::testing::Test
{
protected:
    ke_scheduler_handle scheduler_h{};
    ke_ecs_handle       ecs_h{};
    ke_runtime_handle   runtime_h{};
    ke_scheduler       *scheduler = nullptr;
    ke_ecs             *ecs       = nullptr;
    ke_runtime         *runtime   = nullptr;

    ke_component_id pos = 0;
    ke_entity       entity{};

    void SetUp() override
    {
        g_render_column   = nullptr;
        g_render_segments = 0;
        g_render_value    = 0.0f;
        g_sim_column      = nullptr;

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

        pos = ecs->component_register(ecs, "snap_pos", sizeof(Pos));
        ASSERT_NE(pos, 0u);

        // A single entity: the archetype column base and the entity's own element
        // coincide, so a column pointer can be compared against component_get.
        entity  = ecs->entity_create(ecs);
        Pos *p  = static_cast<Pos *>(ecs->component_add(ecs, entity, pos));
        ASSERT_NE(p, nullptr);
        *p = {1.0f, 0.0f, 0.0f};
    }

    void TearDown() override
    {
        if (runtime_h.ref) runtime_h.destroy(runtime_h.ref);
        if (ecs_h.ref) ecs_h.destroy(ecs_h.ref);
        if (scheduler_h.ref) scheduler_h.destroy(scheduler_h.ref);
    }

    void register_reader(void (*body)(ke_system_ctx *, void *, float), ke_phase phase,
                         const char *name, ke_query_decl *decl)
    {
        decl->terms[0]   = {pos, KE_ACCESS_READ};
        decl->term_count = 1;

        ke_runtime_system_params s{};
        s.name        = name;
        s.phase       = phase;
        s.queries     = decl;
        s.query_count = 1;
        s.execute     = body;
        ASSERT_NE(runtime->register_system(runtime, &s, nullptr), 0u);
    }

    void set_live_x(float v)
    {
        Pos *p = static_cast<Pos *>(ecs->component_get(ecs, entity, pos));
        ASSERT_NE(p, nullptr);
        p->x = v;
    }
};

// Registering a render-phase system that reads a component must give that
// component a snapshot; a sim-only component gets none.
TEST_F(EcsSnapshot, RenderPhaseRead_MarksComponentDoubleBuffered)
{
    ke_component_id sim_only = ecs->component_register(ecs, "sim_only", sizeof(Pos));
    ASSERT_NE(sim_only, 0u);

    ke_query_decl decl{};
    register_reader(render_reader, KE_PHASE_RENDER, "RenderReader", &decl);
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    EXPECT_NE(ecs->snapshot_cid(ecs, pos), pos) << "a render-read component must be double-buffered";
    EXPECT_EQ(ecs->snapshot_cid(ecs, sim_only), sim_only) << "a sim-only component must stay single-buffered";
}

// The regression this guards: a render system's queries were registered against
// the LIVE cids, so ke_system_ctx_view — the path every render pass uses —
// resolved segments over live storage and the snapshot was never read.
TEST_F(EcsSnapshot, RenderView_ResolvesToSnapshotStorage)
{
    ke_query_decl decl{};
    register_reader(render_reader, KE_PHASE_RENDER, "RenderReader", &decl);

    // Two ticks: the first swap adds the snapshot component and moves the entity to
    // a new archetype, so storage pointers only settle from the second tick on.
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    ASSERT_EQ(g_render_segments, 1u) << "render query must match the entity";
    ASSERT_NE(g_render_column, nullptr);

    const ke_component_id snap = ecs->snapshot_cid(ecs, pos);
    ASSERT_NE(snap, pos);

    const void *snap_storage = ecs->component_get(ecs, entity, snap);
    const void *live_storage = ecs->component_get(ecs, entity, pos);
    ASSERT_NE(snap_storage, nullptr);
    ASSERT_NE(live_storage, nullptr);
    ASSERT_NE(snap_storage, live_storage);

    EXPECT_EQ(g_render_column, snap_storage) << "render view must read the snapshot side";
    EXPECT_NE(g_render_column, live_storage) << "render view must not read the live side";
}

// The mirror image: a sim-phase system reads live, never the snapshot, even once
// the component has been marked double-buffered by some render system.
TEST_F(EcsSnapshot, SimView_ResolvesToLiveStorage)
{
    ke_query_decl render_decl{};
    ke_query_decl sim_decl{};
    register_reader(render_reader, KE_PHASE_RENDER, "RenderReader", &render_decl);
    register_reader(sim_reader, KE_PHASE_UPDATE, "SimReader", &sim_decl);

    // Two ticks: the first swap is what adds the snapshot component, which moves the
    // entity to a new archetype. Comparing storage pointers is only meaningful once
    // the archetype has settled, i.e. from the second tick on.
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));

    ASSERT_NE(g_sim_column, nullptr);
    EXPECT_EQ(g_sim_column, ecs->component_get(ecs, entity, pos)) << "sim view must read the live side";
    EXPECT_NE(g_sim_column, g_render_column) << "sim and render must read different storage";
}

// The back buffer is a real frame boundary: a live write landing after the swap
// is not visible to the snapshot until the next swap hands it over.
TEST_F(EcsSnapshot, SnapshotLagsLiveByOneSwap)
{
    ke_query_decl decl{};
    register_reader(render_reader, KE_PHASE_RENDER, "RenderReader", &decl);

    set_live_x(10.0f);
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    EXPECT_FLOAT_EQ(g_render_value, 10.0f) << "the swap must hand the sim's write to render";

    // Write live after this tick's swap: the snapshot still holds the old value.
    set_live_x(20.0f);
    const Pos *snap = static_cast<const Pos *>(ecs->component_get(ecs, entity, ecs->snapshot_cid(ecs, pos)));
    ASSERT_NE(snap, nullptr);
    EXPECT_FLOAT_EQ(snap->x, 10.0f) << "the snapshot must not observe a live write made after the swap";

    // The next tick's swap propagates it.
    ASSERT_TRUE(runtime->tick(runtime, 1.0f / 60.0f, NULL));
    EXPECT_FLOAT_EQ(g_render_value, 20.0f) << "the next swap must hand the newer value to render";
}

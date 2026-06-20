#include <gtest/gtest.h>
#include <kernel_engine/resource_cache/resource_cache.h>

// All tests share the malloc allocator; the cache is single-threaded inside,
// which matches our test execution model.

namespace {

// Cache-wide destroy callback: counts invocations + records the last freed
// handle. State lives in static globals because the destroy_fn is per-cache
// now (Tier 1 decision); per-test state is reset in SetUp.
int                g_destroy_calls   = 0;
ke_resource_handle g_last_destroyed  = KE_RESOURCE_HANDLE_NONE;
int               *g_marker_ctx     = nullptr;

void counting_destroy(ke_resource_handle h, void *) {
    g_destroy_calls++;
    g_last_destroyed = h;
}

void marker_destroy(ke_resource_handle, void *ctx) {
    if (ctx) (*(int *)ctx)++;
}

}  // namespace

class ResourceCacheTest : public ::testing::Test
{
protected:
    ke_resource_cache_handle cache_h{};
    ke_resource_cache *cache = nullptr;

    void SetUp() override
    {
        g_destroy_calls  = 0;
        g_last_destroyed = KE_RESOURCE_HANDLE_NONE;
        g_marker_ctx     = nullptr;

        ke_resource_cache_params params{};
        params.destroy_fn  = counting_destroy;
        params.destroy_ctx = nullptr;
        cache_h = ke_resource_cache_create(&params, NULL);
        ASSERT_NE(cache_h.ref, nullptr);
        cache = cache_h.ref;
    }
    void TearDown() override
    {
        if (cache_h.ref && cache_h.destroy) cache_h.destroy(cache_h.ref);
    }

    void make_cache_with_marker(int *marker) {
        if (cache_h.ref) cache_h.destroy(cache_h.ref);
        ke_resource_cache_params params{};
        params.destroy_fn  = marker_destroy;
        params.destroy_ctx = marker;
        cache_h = ke_resource_cache_create(&params, NULL);
        ASSERT_NE(cache_h.ref, nullptr);
        cache = cache_h.ref;
    }
};

// ── Lifecycle ────────────────────────────────────────────────────────────────

TEST_F(ResourceCacheTest, Register_StartsRefcountAtOne)
{
    ASSERT_TRUE(cache->register_resource(cache, 42, NULL));
    EXPECT_TRUE(cache->release(cache, 42, NULL));
    EXPECT_FALSE(cache->release(cache, 42, NULL));
}

TEST_F(ResourceCacheTest, Register_RejectsNoneHandle)
{
    EXPECT_FALSE(cache->register_resource(cache, KE_RESOURCE_HANDLE_NONE, NULL));
}

TEST_F(ResourceCacheTest, Register_RejectsDuplicate)
{
    ASSERT_TRUE(cache->register_resource(cache, 7, NULL));
    EXPECT_FALSE(cache->register_resource(cache, 7, NULL));
    cache->release(cache, 7, NULL);
}

TEST_F(ResourceCacheTest, Retain_IncrementsRefcount)
{
    ASSERT_TRUE(cache->register_resource(cache, 1, NULL));
    EXPECT_TRUE(cache->retain(cache, 1, NULL));   // 1 → 2
    EXPECT_TRUE(cache->retain(cache, 1, NULL));   // 2 → 3
    EXPECT_TRUE(cache->release(cache, 1, NULL));  // 3 → 2
    EXPECT_EQ(g_destroy_calls, 0);
    EXPECT_TRUE(cache->release(cache, 1, NULL));  // 2 → 1
    EXPECT_EQ(g_destroy_calls, 0);
    EXPECT_TRUE(cache->release(cache, 1, NULL));  // 1 → 0 → destroy
    EXPECT_EQ(g_destroy_calls, 1);
    EXPECT_EQ(g_last_destroyed, 1u);
}

TEST_F(ResourceCacheTest, Retain_UnknownHandle_NotFound)
{
    EXPECT_FALSE(cache->retain(cache, 999, NULL));
}

TEST_F(ResourceCacheTest, Destroy_ForwardsContext)
{
    int marker = 0;
    make_cache_with_marker(&marker);

    ASSERT_TRUE(cache->register_resource(cache, 100, NULL));
    cache->release(cache, 100, NULL);
    EXPECT_EQ(marker, 1);
}

TEST_F(ResourceCacheTest, HandleZero_IsValid)
{
    int marker = 0;
    make_cache_with_marker(&marker);

    ASSERT_TRUE(cache->register_resource(cache, 0, NULL));
    EXPECT_TRUE(cache->retain(cache, 0, NULL));
    EXPECT_TRUE(cache->release(cache, 0, NULL));
    EXPECT_EQ(marker, 0);
    EXPECT_TRUE(cache->release(cache, 0, NULL));
    EXPECT_EQ(marker, 1);
}

// ── Path cache ───────────────────────────────────────────────────────────────

TEST_F(ResourceCacheTest, TryGetCached_MissReturnsFalse)
{
    ke_resource_handle out = 0;
    EXPECT_FALSE(cache->try_get_cached(cache, "res://missing", &out));
}

TEST_F(ResourceCacheTest, InsertThenGet_HitsAndRetains)
{
    ASSERT_TRUE(cache->register_resource(cache, 10, NULL));
    EXPECT_TRUE(cache->cache_insert(cache, "res://x.mesh", 10, NULL));

    ke_resource_handle out = KE_RESOURCE_HANDLE_NONE;
    EXPECT_TRUE(cache->try_get_cached(cache, "res://x.mesh", &out));
    EXPECT_EQ(out, 10u);
    // try_get_cached retained → refcount is 2. Releasing once doesn't free.
    EXPECT_TRUE(cache->release(cache, 10, NULL));
    EXPECT_EQ(g_destroy_calls, 0);
    EXPECT_TRUE(cache->release(cache, 10, NULL));
    EXPECT_EQ(g_destroy_calls, 1);
}

TEST_F(ResourceCacheTest, CacheInsert_DuplicateKey_ReturnsInvalidArgument)
{
    ASSERT_TRUE(cache->register_resource(cache, 20, NULL));
    ASSERT_TRUE(cache->register_resource(cache, 21, NULL));
    EXPECT_TRUE(cache->cache_insert(cache, "res://y.tex", 20, NULL));
    // Duplicate key — caller must try_get_cached first.
    EXPECT_FALSE(cache->cache_insert(cache, "res://y.tex", 21, NULL));
    cache->release(cache, 20, NULL);
    cache->release(cache, 21, NULL);
}

TEST_F(ResourceCacheTest, Release_EvictsAssociatedPath)
{
    ASSERT_TRUE(cache->register_resource(cache, 20, NULL));
    ASSERT_TRUE(cache->cache_insert(cache, "res://y.tex", 20, NULL));

    cache->release(cache, 20, NULL);

    ke_resource_handle out = 0;
    EXPECT_FALSE(cache->try_get_cached(cache, "res://y.tex", &out));
}

TEST_F(ResourceCacheTest, CacheEvict_RemovesPathButKeepsResource)
{
    ASSERT_TRUE(cache->register_resource(cache, 30, NULL));
    ASSERT_TRUE(cache->cache_insert(cache, "res://z.mat", 30, NULL));

    cache->cache_evict(cache, "res://z.mat");
    ke_resource_handle out = 0;
    EXPECT_FALSE(cache->try_get_cached(cache, "res://z.mat", &out));
    // Resource itself is still alive (refcount = 1 from register).
    EXPECT_EQ(g_destroy_calls, 0);
    cache->release(cache, 30, NULL);
    EXPECT_EQ(g_destroy_calls, 1);
}

// ── Capacity / rehash ────────────────────────────────────────────────────────

TEST_F(ResourceCacheTest, HandlesManyInsertionsThroughRehash)
{
    constexpr uint32_t N = 200;
    for (uint32_t i = 1; i <= N; i++) {
        ASSERT_TRUE(cache->register_resource(cache, i, NULL)) << "i=" << i;
    }
    for (uint32_t i = 1; i <= N; i++) {
        EXPECT_TRUE(cache->retain(cache, i, NULL))  << "i=" << i;
        EXPECT_TRUE(cache->release(cache, i, NULL)) << "i=" << i;
    }
    for (uint32_t i = 1; i <= N; i++) cache->release(cache, i, NULL);
}

TEST_F(ResourceCacheTest, ReinsertionAfterReleaseReusesTombstone)
{
    ASSERT_TRUE(cache->register_resource(cache, 1, NULL));
    cache->release(cache, 1, NULL);
    ASSERT_TRUE(cache->register_resource(cache, 65, NULL));  // collides with 1 mod 64
    EXPECT_TRUE(cache->retain(cache, 65, NULL));
    cache->release(cache, 65, NULL);
    cache->release(cache, 65, NULL);
    EXPECT_FALSE(cache->retain(cache, 65, NULL));
}

// ── Edge cases ───────────────────────────────────────────────────────────────

TEST_F(ResourceCacheTest, TryGetCached_ReturnsFalse_WhenResourceWasReleasedExternally)
{
    EXPECT_TRUE(cache->cache_insert(cache, "res://stale", 500, NULL));
    ke_resource_handle out = 0;
    EXPECT_FALSE(cache->try_get_cached(cache, "res://stale", &out));
}

TEST_F(ResourceCacheTest, CacheInsert_NullArgs_ReturnsInvalidArgument)
{
    EXPECT_FALSE(cache->cache_insert(nullptr, nullptr, 0, NULL));
    EXPECT_FALSE(cache->cache_insert(cache, nullptr, 0, NULL));
    EXPECT_FALSE(cache->cache_insert(cache, "x", KE_RESOURCE_HANDLE_NONE, NULL));
}

TEST_F(ResourceCacheTest, CacheEvict_NullArgs_DoesNotCrash)
{
    cache->cache_evict(nullptr, nullptr);
    cache->cache_evict(cache, nullptr);
}

TEST_F(ResourceCacheTest, TombstoneReuse)
{
    cache->register_resource(cache, 1, NULL);
    cache->register_resource(cache, 2, NULL);

    cache->release(cache, 1, NULL);

    EXPECT_TRUE(cache->register_resource(cache, 3, NULL));

    ke_resource_handle out;
    EXPECT_TRUE(cache->cache_insert(cache, "res://3", 3, NULL));
    EXPECT_TRUE(cache->try_get_cached(cache, "res://3", &out));
    EXPECT_EQ(out, 3u);
}

TEST_F(ResourceCacheTest, Rehash_WithTombstones)
{
    for (int i = 1; i <= 40; ++i) {
        cache->register_resource(cache, (ke_resource_handle)i, NULL);
    }
    for (int i = 1; i <= 20; ++i) {
        cache->release(cache, (ke_resource_handle)i, NULL);
    }
    for (int i = 41; i <= 100; ++i) {
        ASSERT_TRUE(cache->register_resource(cache, (ke_resource_handle)i, NULL));
    }

    ke_resource_handle out;
    EXPECT_FALSE(cache->try_get_cached(cache, "res://missing", &out));
}

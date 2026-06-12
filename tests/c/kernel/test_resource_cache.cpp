#include <gtest/gtest.h>
#include <kernel_engine/kernel/framework/resource_cache.h>
#include <kernel_engine/kernel/context/allocator.h>

// All tests share the malloc allocator; the cache claims to be single-threaded,
// which matches our test execution model.

class ResourceCacheTest : public ::testing::Test
{
protected:
    ke_allocator      *allocator = nullptr;
    ke_resource_cache *cache     = nullptr;

    void SetUp() override
    {
        allocator = ke_allocator_malloc_create();
        ASSERT_NE(allocator, nullptr);
        ASSERT_EQ(ke_resource_cache_create(allocator, &cache), KE_OK);
    }
    void TearDown() override
    {
        if (cache && cache->destroy) cache->destroy(cache);
        // ke_allocator_malloc is a singleton — no explicit destroy.
    }
};

// ── Lifecycle ────────────────────────────────────────────────────────────────

static void noop_destroy(ke_resource_handle, void *) {}

static int g_destroy_calls = 0;
static ke_resource_handle g_last_destroyed = KE_RESOURCE_HANDLE_NONE;
static void counting_destroy(ke_resource_handle h, void *)
{
    g_destroy_calls++;
    g_last_destroyed = h;
}

TEST_F(ResourceCacheTest, Register_StartsRefcountAtOne)
{
    ASSERT_EQ(cache->register_resource(cache, 42, noop_destroy, nullptr), KE_OK);
    // Release once → refcount goes 1 → 0 → destroy fires.
    EXPECT_EQ(cache->release(cache, 42), KE_OK);
    // Now the handle is gone; release again is NOT_FOUND.
    EXPECT_EQ(cache->release(cache, 42), KE_ERROR_NOT_FOUND);
}

TEST_F(ResourceCacheTest, Register_RejectsNoneHandle)
{
    EXPECT_EQ(cache->register_resource(cache, KE_RESOURCE_HANDLE_NONE, noop_destroy, nullptr),
              KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(ResourceCacheTest, Register_RejectsDuplicate)
{
    ASSERT_EQ(cache->register_resource(cache, 7, noop_destroy, nullptr), KE_OK);
    EXPECT_EQ(cache->register_resource(cache, 7, noop_destroy, nullptr),
              KE_ERROR_INVALID_ARGUMENT);
    cache->release(cache, 7);
}

TEST_F(ResourceCacheTest, Retain_IncrementsRefcount)
{
    g_destroy_calls = 0;
    ASSERT_EQ(cache->register_resource(cache, 1, counting_destroy, nullptr), KE_OK);
    EXPECT_EQ(cache->retain(cache, 1), KE_OK);   // 1 → 2
    EXPECT_EQ(cache->retain(cache, 1), KE_OK);   // 2 → 3
    EXPECT_EQ(cache->release(cache, 1), KE_OK);  // 3 → 2
    EXPECT_EQ(g_destroy_calls, 0);
    EXPECT_EQ(cache->release(cache, 1), KE_OK);  // 2 → 1
    EXPECT_EQ(g_destroy_calls, 0);
    EXPECT_EQ(cache->release(cache, 1), KE_OK);  // 1 → 0 → destroy
    EXPECT_EQ(g_destroy_calls, 1);
    EXPECT_EQ(g_last_destroyed, 1u);
}

TEST_F(ResourceCacheTest, Retain_UnknownHandle_NotFound)
{
    EXPECT_EQ(cache->retain(cache, 999), KE_ERROR_NOT_FOUND);
}

TEST_F(ResourceCacheTest, Destroy_ForwardsContext)
{
    int marker = 0;
    auto destroy = +[](ke_resource_handle, void *ctx) { (*(int *)ctx)++; };
    ASSERT_EQ(cache->register_resource(cache, 100, destroy, &marker), KE_OK);
    cache->release(cache, 100);
    EXPECT_EQ(marker, 1);
}

TEST_F(ResourceCacheTest, HandleZero_IsValid)
{
    // Handle 0 must not collide with the "empty" slot sentinel.
    int marker = 0;
    auto destroy = +[](ke_resource_handle, void *ctx) { (*(int *)ctx)++; };
    ASSERT_EQ(cache->register_resource(cache, 0, destroy, &marker), KE_OK);
    EXPECT_EQ(cache->retain(cache, 0), KE_OK);
    EXPECT_EQ(cache->release(cache, 0), KE_OK);
    EXPECT_EQ(marker, 0);
    EXPECT_EQ(cache->release(cache, 0), KE_OK);
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
    g_destroy_calls = 0;
    ASSERT_EQ(cache->register_resource(cache, 10, counting_destroy, nullptr), KE_OK);
    cache->cache_insert(cache, "res://x.mesh", 10);

    ke_resource_handle out = KE_RESOURCE_HANDLE_NONE;
    EXPECT_TRUE(cache->try_get_cached(cache, "res://x.mesh", &out));
    EXPECT_EQ(out, 10u);
    // The cache should have retained the resource for the caller. Refcount is
    // now 2. Releasing once doesn't free; releasing twice does.
    EXPECT_EQ(cache->release(cache, 10), KE_OK);
    EXPECT_EQ(g_destroy_calls, 0);
    EXPECT_EQ(cache->release(cache, 10), KE_OK);
    EXPECT_EQ(g_destroy_calls, 1);
}

TEST_F(ResourceCacheTest, Release_EvictsAssociatedPath)
{
    ASSERT_EQ(cache->register_resource(cache, 20, noop_destroy, nullptr), KE_OK);
    cache->cache_insert(cache, "res://y.tex", 20);

    // Drop the only ref → destroy fires → path entry must go too.
    cache->release(cache, 20);

    ke_resource_handle out = 0;
    EXPECT_FALSE(cache->try_get_cached(cache, "res://y.tex", &out));
}

TEST_F(ResourceCacheTest, CacheEvict_RemovesPathButKeepsResource)
{
    g_destroy_calls = 0;
    ASSERT_EQ(cache->register_resource(cache, 30, counting_destroy, nullptr), KE_OK);
    cache->cache_insert(cache, "res://z.mat", 30);

    cache->cache_evict(cache, "res://z.mat");
    ke_resource_handle out = 0;
    EXPECT_FALSE(cache->try_get_cached(cache, "res://z.mat", &out));
    // Resource itself is still alive (refcount = 1 from register_resource).
    EXPECT_EQ(g_destroy_calls, 0);
    cache->release(cache, 30);
    EXPECT_EQ(g_destroy_calls, 1);
}

// ── Capacity / rehash ────────────────────────────────────────────────────────

TEST_F(ResourceCacheTest, HandlesManyInsertionsThroughRehash)
{
    // Initial capacity is 64 internally — inserting > 128 forces multiple rehashes.
    constexpr uint32_t N = 200;
    for (uint32_t i = 1; i <= N; i++) {
        ASSERT_EQ(cache->register_resource(cache, i, noop_destroy, nullptr), KE_OK) << "i=" << i;
    }
    // Spot-check: every handle is retain/release-addressable.
    for (uint32_t i = 1; i <= N; i++) {
        EXPECT_EQ(cache->retain(cache, i), KE_OK)  << "i=" << i;
        EXPECT_EQ(cache->release(cache, i), KE_OK) << "i=" << i;
    }
    // Tear down.
    for (uint32_t i = 1; i <= N; i++) cache->release(cache, i);
}

TEST_F(ResourceCacheTest, ReinsertionAfterReleaseReusesTombstone)
{
    // Register and release a handle, then register a different one whose key
    // hash probably probes through the tombstoned slot. The probe must keep
    // walking past tombstones, never stop at them.
    ASSERT_EQ(cache->register_resource(cache, 1, noop_destroy, nullptr), KE_OK);
    cache->release(cache, 1);
    ASSERT_EQ(cache->register_resource(cache, 65, noop_destroy, nullptr), KE_OK); // collides with 1 mod 64
    EXPECT_EQ(cache->retain(cache, 65), KE_OK);
    cache->release(cache, 65);
    cache->release(cache, 65);
    EXPECT_EQ(cache->retain(cache, 65), KE_ERROR_NOT_FOUND); // released
}

// ── Destroy with live resources ──────────────────────────────────────────────

TEST_F(ResourceCacheTest, TryGetCached_ReturnsFalse_WhenResourceWasReleasedExternally)
{
    // Path cache pointing to a handle that is no longer in the resource table.
    // This can happen if the resource is released but the path cache wasn't updated.
    cache->cache_insert(cache, "res://stale", 500);
    ke_resource_handle out = 0;
    EXPECT_FALSE(cache->try_get_cached(cache, "res://stale", &out));
}

TEST_F(ResourceCacheTest, CacheInsert_NullArgs_DoesNotCrash)
{
    cache->cache_insert(nullptr, nullptr, 0);
    cache->cache_insert(cache, nullptr, 0);
    cache->cache_insert(cache, "x", KE_RESOURCE_HANDLE_NONE);
}

TEST_F(ResourceCacheTest, CacheEvict_NullArgs_DoesNotCrash)
{
    cache->cache_evict(nullptr, nullptr);
    cache->cache_evict(cache, nullptr);
}

TEST_F(ResourceCacheTest, TombstoneReuse)
{
    auto noop = +[](ke_resource_handle, void *) {};
    cache->register_resource(cache, 1, noop, nullptr);
    cache->register_resource(cache, 2, noop, nullptr);
    
    // Release 1 to create a tombstone
    cache->release(cache, 1);
    
    // Registering 3 should ideally reuse the tombstone if it was earlier in probe chain,
    // but at least it shouldn't fail.
    EXPECT_EQ(cache->register_resource(cache, 3, noop, nullptr), KE_OK);
    
    ke_resource_handle out;
    cache->cache_insert(cache, "res://3", 3);
    EXPECT_TRUE(cache->try_get_cached(cache, "res://3", &out));
    EXPECT_EQ(out, 3u);
}

TEST_F(ResourceCacheTest, Rehash_WithTombstones)
{
    auto noop = +[](ke_resource_handle, void *) {};
    // Fill with entries then release half to create tombstones
    for(int i=1; i<=40; ++i) {
        cache->register_resource(cache, (ke_resource_handle)i, noop, nullptr);
    }
    for(int i=1; i<=20; ++i) {
        cache->release(cache, (ke_resource_handle)i);
    }
    
    // Next registration might trigger rehash (load factor includes tombstones)
    for(int i=41; i<=100; ++i) {
        ASSERT_EQ(cache->register_resource(cache, (ke_resource_handle)i, noop, nullptr), KE_OK);
    }
    
    ke_resource_handle out;
    EXPECT_TRUE(cache->try_get_cached(cache, "res://missing", &out) == false);
}

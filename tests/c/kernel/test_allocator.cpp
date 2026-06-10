#include <gtest/gtest.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <stdint.h>
#include <string.h>

// --- Malloc Allocator Tests ---

TEST(MallocAllocatorInitTest, Create_ReturnsNonNull) {
    ke_allocator* a = ke_allocator_malloc_create();
    ASSERT_NE(a, nullptr);
    a->destroy(a);
}

class MallocAllocatorTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    void SetUp() override { alloc = ke_allocator_malloc_create(); }
    void TearDown() override { if (alloc) alloc->destroy(alloc); }
};

TEST_F(MallocAllocatorTest, Alloc_ReturnsNonNull) {
    void* ptr = alloc->alloc(alloc, 100, 0);
    ASSERT_NE(ptr, nullptr);
    alloc->free(alloc, ptr);
}

TEST_F(MallocAllocatorTest, Alloc_AllowsZeroAlignment) {
    void* ptr = alloc->alloc(alloc, 100, 0);
    ASSERT_NE(ptr, nullptr);
    alloc->free(alloc, ptr);
}

TEST_F(MallocAllocatorTest, Realloc_ReturnsNonNull) {
    void* ptr = alloc->alloc(alloc, 50, 0);
    void* new_ptr = alloc->realloc(alloc, ptr, 200);
    ASSERT_NE(new_ptr, nullptr);
    alloc->free(alloc, new_ptr);
}

// --- Arena Allocator Tests ---

TEST(ArenaAllocatorInitTest, Create_ReturnsNonNull) {
    ke_allocator* a = ke_allocator_arena_create(1024);
    ASSERT_NE(a, nullptr);
    a->destroy(a);
}

class ArenaAllocatorTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    const size_t capacity = 1024;
    void SetUp() override { alloc = ke_allocator_arena_create(capacity); }
    void TearDown() override { if (alloc) alloc->destroy(alloc); }
};

TEST_F(ArenaAllocatorTest, Alloc_ReturnsNonNull) {
    ASSERT_NE(alloc->alloc(alloc, 100, 0), nullptr);
}

TEST_F(ArenaAllocatorTest, Alloc_SuccessiveCalls_ReturnDifferentPointers) {
    void* p1 = alloc->alloc(alloc, 10, 0);
    void* p2 = alloc->alloc(alloc, 10, 0);
    ASSERT_NE(p1, p2);
}

TEST_F(ArenaAllocatorTest, Alloc_Alignment_16) {
    void* ptr = alloc->alloc(alloc, 10, 16);
    ASSERT_EQ((uintptr_t)ptr % 16, 0);
}

TEST_F(ArenaAllocatorTest, Alloc_Alignment_32) {
    void* ptr = alloc->alloc(alloc, 10, 32);
    ASSERT_EQ((uintptr_t)ptr % 32, 0);
}

TEST_F(ArenaAllocatorTest, Alloc_DefaultAlignment_Is8) {
    // Offset 1, next should align to 8
    alloc->alloc(alloc, 1, 1); 
    void* ptr = alloc->alloc(alloc, 1, 0);
    ASSERT_EQ((uintptr_t)ptr % 8, 0);
}

TEST_F(ArenaAllocatorTest, Alloc_Full_ReturnsNull) {
    ASSERT_EQ(alloc->alloc(alloc, capacity + 1, 0), nullptr);
}

TEST_F(ArenaAllocatorTest, Reset_AllowsReuse) {
    void* p1 = alloc->alloc(alloc, 10, 0);
    alloc->reset(alloc);
    void* p2 = alloc->alloc(alloc, 10, 0);
    ASSERT_EQ(p1, p2);
}

TEST_F(ArenaAllocatorTest, Realloc_NullPtr_BehavesLikeAlloc) {
    void* ptr = alloc->realloc(alloc, nullptr, 100);
    ASSERT_NE(ptr, nullptr);
}

TEST_F(ArenaAllocatorTest, Realloc_Growing_ReturnsNewPointer) {
    void* p1 = alloc->alloc(alloc, 10, 0);
    void* p2 = alloc->realloc(alloc, p1, 20);
    ASSERT_NE(p1, p2);
}

TEST_F(ArenaAllocatorTest, Realloc_FailsWhenFull_ReturnsNull) {
    void* p1 = alloc->alloc(alloc, 10, 0);
    // Almost fill it
    alloc->alloc(alloc, capacity - 20, 0);
    // Try to realloc p1 to something that won't fit
    ASSERT_EQ(alloc->realloc(alloc, p1, 100), nullptr);
}

// --- Whitebox / Sanity Checks ---

TEST_F(ArenaAllocatorTest, Alloc_NullHandle_ReturnsNull) {
    void* original = alloc->handle;
    alloc->handle = nullptr;
    void* ptr = alloc->alloc(alloc, 10, 0);
    alloc->handle = original;
    ASSERT_EQ(ptr, nullptr);
}

typedef struct {
    uint8_t *buffer;
    size_t capacity;
    size_t offset;
} mock_arena;

TEST_F(ArenaAllocatorTest, Alloc_NullBuffer_ReturnsNull) {
    mock_arena* arena = (mock_arena*)alloc->handle;
    uint8_t* original_buf = arena->buffer;
    arena->buffer = nullptr;
    void* ptr = alloc->alloc(alloc, 10, 0);
    arena->buffer = original_buf;
    ASSERT_EQ(ptr, nullptr);
}

TEST_F(ArenaAllocatorTest, Reset_NullHandle_DoesNotCrash) {
    void* original = alloc->handle;
    alloc->handle = nullptr;
    alloc->reset(alloc);
    alloc->handle = original;
    SUCCEED();
}

TEST_F(ArenaAllocatorTest, Reset_WithNullHandle_NoEffect) {
    void* original = alloc->handle;
    alloc->handle = nullptr;
    alloc->reset(alloc);
    alloc->handle = original;
    // Just verifying it doesn't crash and we can still use it after restoring handle
    ASSERT_NE(alloc->alloc(alloc, 10, 0), nullptr);
}

TEST(AllocatorStaticTest, ArenaDestroy_NullSelf_DoesNotCrash) {
    ke_allocator* a = ke_allocator_arena_create(64);
    auto destroy_ptr = a->destroy;
    a->destroy(a);
    
    destroy_ptr(nullptr);
    SUCCEED();
}

// --- Proxy Allocator Tests ---

TEST(ProxyAllocatorInitTest, Create_ReturnsNonNull) {
    ke_allocator* inner = ke_allocator_malloc_create();
    ke_allocator* proxy = ke_allocator_proxy_create(inner, "Test");
    ASSERT_NE(proxy, nullptr);
    proxy->destroy(proxy);
    inner->destroy(inner);
}

TEST(ProxyAllocatorInitTest, Create_WithNullInner_ReturnsNull) {
    ASSERT_EQ(ke_allocator_proxy_create(nullptr, "Test"), nullptr);
}

class ProxyAllocatorTest : public ::testing::Test {
protected:
    ke_allocator* inner = nullptr;
    ke_allocator* proxy = nullptr;
    void SetUp() override { 
        inner = ke_allocator_malloc_create(); 
        proxy = ke_allocator_proxy_create(inner, "Test");
    }
    void TearDown() override { 
        if (proxy) proxy->destroy(proxy); 
        if (inner) inner->destroy(inner);
    }
};

TEST_F(ProxyAllocatorTest, Alloc_TracksStats) {
    void* p = proxy->alloc(proxy, 100, 0);
    ke_allocator_stats stats;
    ke_allocator_proxy_get_stats(proxy, &stats);
    
    EXPECT_EQ(stats.active_allocs, 1);
    EXPECT_EQ(stats.active_bytes, 100);
    proxy->free(proxy, p);
}

TEST_F(ProxyAllocatorTest, Free_UpdatesStats) {
    void* p = proxy->alloc(proxy, 100, 0);
    proxy->free(proxy, p);
    
    ke_allocator_stats stats;
    ke_allocator_proxy_get_stats(proxy, &stats);
    EXPECT_EQ(stats.active_allocs, 0);
    EXPECT_EQ(stats.active_bytes, 0);
    EXPECT_EQ(stats.total_freed, 100);
}

TEST_F(ProxyAllocatorTest, Realloc_UpdatesStats) {
    void* p = proxy->alloc(proxy, 100, 0);
    void* p2 = proxy->realloc(proxy, p, 200);
    
    ke_allocator_stats stats;
    ke_allocator_proxy_get_stats(proxy, &stats);
    EXPECT_EQ(stats.active_bytes, 200);
    EXPECT_EQ(stats.total_allocated, 300); // 100 + 200
    
    proxy->free(proxy, p2);
}

TEST_F(ProxyAllocatorTest, Report_Works) {
    void* p = proxy->alloc(proxy, 100, 0);
    ke_allocator_proxy_report(proxy, nullptr); // To stderr
    proxy->free(proxy, p);
}

TEST_F(ProxyAllocatorTest, GetStats_NullArgs_ReturnsInvalidArgument) {
    EXPECT_EQ(ke_allocator_proxy_get_stats(nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(ProxyAllocatorTest, ProxyAlloc_NullHandle_ReturnsNull) {
    void* original = proxy->handle;
    proxy->handle = nullptr;
    void* ptr = proxy->alloc(proxy, 10, 0);
    proxy->handle = original;
    ASSERT_EQ(ptr, nullptr);
}

TEST_F(ProxyAllocatorTest, ProxyFree_NullHandle_DoesNotCrash) {
    void* original = proxy->handle;
    proxy->handle = nullptr;
    proxy->free(proxy, nullptr);
    proxy->handle = original;
    SUCCEED();
}

TEST_F(ProxyAllocatorTest, ProxyReport_WithLogger_Works) {
    ke_allocator* a = ke_allocator_malloc_create();
    ke_allocator* p = ke_allocator_proxy_create(a, "L");
    ke_allocator_proxy_report(p, nullptr); // stderr
    p->destroy(p);
    a->destroy(a);
}

TEST_F(ArenaAllocatorTest, ArenaAlloc_ZeroSize_ReturnsNull) {
    ASSERT_EQ(alloc->alloc(alloc, 0, 0), nullptr);
}

TEST_F(ArenaAllocatorTest, ArenaRealloc_ToZero_FreesAndReturnsNull) {
    void* p = alloc->alloc(alloc, 10, 0);
    void* p2 = alloc->realloc(alloc, p, 0);
    ASSERT_EQ(p2, nullptr);
}

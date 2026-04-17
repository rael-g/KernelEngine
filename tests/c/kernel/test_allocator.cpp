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

TEST(AllocatorStaticTest, ArenaReset_NullSelf_DoesNotCrash) {
    ke_allocator* a = ke_allocator_arena_create(64);
    auto reset_ptr = a->reset;
    a->destroy(a);
    
    reset_ptr(nullptr);
    SUCCEED();
}

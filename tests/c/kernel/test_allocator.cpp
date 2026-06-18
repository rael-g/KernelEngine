#include <gtest/gtest.h>
#include <kernel_engine/allocator/allocator.h>
#include <stdint.h>
#include <string.h>

// --- ke_alloc / ke_free / ke_realloc Tests ---

TEST(HeapAllocTest, Alloc_ReturnsNonNull) {
    void* ptr = ke_alloc(100, 0);
    ASSERT_NE(ptr, nullptr);
    ke_free(ptr);
}

TEST(HeapAllocTest, Alloc_ZeroSize_ReturnsNull) {
    void* ptr = ke_alloc(0, 0);
    ASSERT_EQ(ptr, nullptr);
}

TEST(HeapAllocTest, Alloc_Alignment16_IsAligned) {
    void* ptr = ke_alloc(64, 16);
    ASSERT_NE(ptr, nullptr);
    EXPECT_EQ((uintptr_t)ptr % 16, 0u);
    ke_free(ptr);
}

TEST(HeapAllocTest, Alloc_Alignment32_IsAligned) {
    void* ptr = ke_alloc(64, 32);
    ASSERT_NE(ptr, nullptr);
    EXPECT_EQ((uintptr_t)ptr % 32, 0u);
    ke_free(ptr);
}

TEST(HeapAllocTest, Free_Null_IsSafe) {
    ke_free(nullptr);
    SUCCEED();
}

TEST(HeapAllocTest, Realloc_GrowsBuffer) {
    void* ptr = ke_alloc(50, 0);
    ASSERT_NE(ptr, nullptr);
    memset(ptr, 0xAB, 50);
    void* new_ptr = ke_realloc(ptr, 200);
    ASSERT_NE(new_ptr, nullptr);
    // First 50 bytes must be preserved
    uint8_t* bytes = (uint8_t*)new_ptr;
    for (int i = 0; i < 50; ++i) EXPECT_EQ(bytes[i], 0xAB);
    ke_free(new_ptr);
}

TEST(HeapAllocTest, Realloc_NullPtr_BehavesLikeAlloc) {
    void* ptr = ke_realloc(nullptr, 100);
    ASSERT_NE(ptr, nullptr);
    ke_free(ptr);
}

TEST(HeapAllocTest, Realloc_ZeroSize_FreesAndReturnsNull) {
    void* ptr = ke_alloc(50, 0);
    ASSERT_NE(ptr, nullptr);
    void* result = ke_realloc(ptr, 0);
    ASSERT_EQ(result, nullptr);
}

// --- ke_arena Tests ---

TEST(ArenaAllocTest, Init_Alloc_Destroy) {
    ke_arena arena{};
    ke_arena_init(&arena, 1024);
    ASSERT_NE(arena.buffer, nullptr);
    ASSERT_EQ(arena.capacity, 1024u);
    ASSERT_EQ(arena.offset, 0u);
    ke_arena_destroy(&arena);
}

TEST(ArenaAllocTest, Alloc_ReturnsNonNull) {
    ke_arena arena{};
    ke_arena_init(&arena, 1024);
    void* ptr = ke_arena_alloc(&arena, 100, 0);
    ASSERT_NE(ptr, nullptr);
    ke_arena_destroy(&arena);
}

TEST(ArenaAllocTest, Alloc_ZeroSize_ReturnsNull) {
    ke_arena arena{};
    ke_arena_init(&arena, 1024);
    void* ptr = ke_arena_alloc(&arena, 0, 0);
    ASSERT_EQ(ptr, nullptr);
    ke_arena_destroy(&arena);
}

TEST(ArenaAllocTest, Alloc_SuccessiveCalls_ReturnDifferentPointers) {
    ke_arena arena{};
    ke_arena_init(&arena, 1024);
    void* p1 = ke_arena_alloc(&arena, 10, 0);
    void* p2 = ke_arena_alloc(&arena, 10, 0);
    ASSERT_NE(p1, p2);
    ke_arena_destroy(&arena);
}

TEST(ArenaAllocTest, Alloc_Alignment16) {
    ke_arena arena{};
    ke_arena_init(&arena, 1024);
    void* ptr = ke_arena_alloc(&arena, 10, 16);
    ASSERT_NE(ptr, nullptr);
    EXPECT_EQ((uintptr_t)ptr % 16, 0u);
    ke_arena_destroy(&arena);
}

TEST(ArenaAllocTest, Alloc_Alignment32) {
    ke_arena arena{};
    ke_arena_init(&arena, 1024);
    void* ptr = ke_arena_alloc(&arena, 10, 32);
    ASSERT_NE(ptr, nullptr);
    EXPECT_EQ((uintptr_t)ptr % 32, 0u);
    ke_arena_destroy(&arena);
}

TEST(ArenaAllocTest, Alloc_Full_ReturnsNull) {
    ke_arena arena{};
    ke_arena_init(&arena, 64);
    void* ptr = ke_arena_alloc(&arena, 65, 0);
    ASSERT_EQ(ptr, nullptr);
    ke_arena_destroy(&arena);
}

TEST(ArenaAllocTest, Reset_AllowsReuse) {
    ke_arena arena{};
    ke_arena_init(&arena, 1024);
    void* p1 = ke_arena_alloc(&arena, 10, 1);
    ke_arena_reset(&arena);
    void* p2 = ke_arena_alloc(&arena, 10, 1);
    ASSERT_EQ(p1, p2);
    ke_arena_destroy(&arena);
}

TEST(ArenaAllocTest, Destroy_NullArena_IsSafe) {
    ke_arena_destroy(nullptr);
    SUCCEED();
}

TEST(ArenaAllocTest, Reset_NullArena_IsSafe) {
    ke_arena_reset(nullptr);
    SUCCEED();
}

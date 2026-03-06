#include <gtest/gtest.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <stdint.h>

class MallocAllocatorTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
    }

    void TearDown() override {
        if (alloc) {
            alloc->destroy(alloc);
        }
    }
};

TEST_F(MallocAllocatorTest, BasicAllocation) {
    void* ptr = alloc->alloc(alloc, 100, 0);
    ASSERT_NE(ptr, nullptr);
    
    // Write some data
    uint8_t* data = (uint8_t*)ptr;
    for(int i=0; i<100; ++i) data[i] = (uint8_t)i;
    
    alloc->free(alloc, ptr);
}

TEST_F(MallocAllocatorTest, Reallocation) {
    void* ptr = alloc->alloc(alloc, 50, 0);
    ASSERT_NE(ptr, nullptr);
    
    void* new_ptr = alloc->realloc(alloc, ptr, 200);
    ASSERT_NE(new_ptr, nullptr);
    
    alloc->free(alloc, new_ptr);
}

class ArenaAllocatorTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    const size_t capacity = 1024;

    void SetUp() override {
        alloc = ke_allocator_arena_create(capacity);
        ASSERT_NE(alloc, nullptr);
    }

    void TearDown() override {
        if (alloc) {
            alloc->destroy(alloc);
        }
    }
};

TEST_F(ArenaAllocatorTest, BasicAllocation) {
    void* ptr1 = alloc->alloc(alloc, 100, 0);
    ASSERT_NE(ptr1, nullptr);
    
    void* ptr2 = alloc->alloc(alloc, 200, 0);
    ASSERT_NE(ptr2, nullptr);
    ASSERT_NE(ptr1, ptr2);
}

TEST_F(ArenaAllocatorTest, Alignment) {
    // Test 16-byte alignment
    void* ptr = alloc->alloc(alloc, 10, 16);
    ASSERT_EQ((uintptr_t)ptr % 16, 0);
    
    void* ptr2 = alloc->alloc(alloc, 10, 32);
    ASSERT_EQ((uintptr_t)ptr2 % 32, 0);
}

TEST_F(ArenaAllocatorTest, OutOfMemory) {
    void* ptr = alloc->alloc(alloc, capacity + 1, 0);
    ASSERT_EQ(ptr, nullptr);
}

TEST_F(ArenaAllocatorTest, Reset) {
    void* ptr1 = alloc->alloc(alloc, 500, 0);
    ASSERT_NE(ptr1, nullptr);
    
    alloc->reset(alloc);
    
    void* ptr2 = alloc->alloc(alloc, 500, 0);
    ASSERT_NE(ptr2, nullptr);
    // After reset, it should reuse the same space
    ASSERT_EQ(ptr1, ptr2);
}

TEST_F(ArenaAllocatorTest, Reallocation) {
    void* ptr = alloc->alloc(alloc, 100, 0);
    ASSERT_NE(ptr, nullptr);
    
    void* new_ptr = alloc->realloc(alloc, ptr, 200);
    ASSERT_NE(new_ptr, nullptr);
    ASSERT_NE(ptr, new_ptr);
}

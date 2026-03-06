#include <gtest/gtest.h>
#include <kernel_engine/kernel/common/hash_map.h>
#include <kernel_engine/kernel/context/allocator.h>

class HashMapTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_hash_map map;
    bool map_initialized = false;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_hash_map_init(&map, 128, alloc);
        ASSERT_EQ(res, KE_OK);
        map_initialized = true;
    }

    void TearDown() override {
        if (map_initialized) {
            ke_hash_map_destroy(&map);
        }
        if (alloc) {
            alloc->destroy(alloc);
        }
    }
};

TEST_F(HashMapTest, InsertAndGet) {
    int value = 42;
    ke_result res = ke_hash_map_insert(&map, 123, &value);
    ASSERT_EQ(res, KE_OK);
    
    void* retrieved = ke_hash_map_get(&map, 123);
    ASSERT_EQ(retrieved, &value);
    ASSERT_EQ(*(int*)retrieved, 42);
}

TEST_F(HashMapTest, DuplicateKey) {
    int value1 = 42;
    int value2 = 84;
    ke_hash_map_insert(&map, 123, &value1);
    ke_result res = ke_hash_map_insert(&map, 123, &value2);
    
    // Implementation choice: update or fail. Usually hash maps update.
    ASSERT_EQ(res, KE_OK);
    ASSERT_EQ(ke_hash_map_get(&map, 123), &value2);
}

TEST_F(HashMapTest, GetNonExistent) {
    ASSERT_EQ(ke_hash_map_get(&map, 999), nullptr);
}

TEST_F(HashMapTest, Resize) {
    const int count = 32;
    int values[count];
    for (int i = 0; i < count; ++i) {
        values[i] = i;
        // Use i+1 as key to avoid 0
        ke_result res = ke_hash_map_insert(&map, i + 1, &values[i]);
        ASSERT_EQ(res, KE_OK);
    }
    
    for (int i = 0; i < count; ++i) {
        void* retrieved = ke_hash_map_get(&map, i + 1);
        ASSERT_EQ(retrieved, &values[i]);
        ASSERT_EQ(*(int*)retrieved, i);
    }
}

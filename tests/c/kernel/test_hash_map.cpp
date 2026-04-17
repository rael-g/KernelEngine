#include <gtest/gtest.h>
#include <kernel_engine/kernel/common/hash_map.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <string.h>

class HashMapTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_hash_map map;
    bool map_initialized = false;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_hash_map_init(&map, 16, alloc);
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

// --- Initialization Tests ---

TEST(HashMapInitTest, Init_NullMap_ReturnsInvalidArgument) {
    ke_allocator* a = ke_allocator_malloc_create();
    ASSERT_EQ(ke_hash_map_init(nullptr, 16, a), KE_ERROR_INVALID_ARGUMENT);
    a->destroy(a);
}

TEST(HashMapInitTest, Init_NullAllocator_ReturnsInvalidArgument) {
    ke_hash_map m;
    ASSERT_EQ(ke_hash_map_init(&m, 16, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

static void* fail_alloc(ke_allocator* alloc, size_t size, size_t alignment) { return nullptr; }
static void* fail_realloc(ke_allocator* alloc, void* ptr, size_t size) { return nullptr; }
static void fail_free(ke_allocator* alloc, void* ptr) {}
static void fail_destroy(ke_allocator* alloc) {}

TEST(HashMapInitTest, Init_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.realloc = fail_realloc;
    fa.free = fail_free;
    fa.destroy = fail_destroy;
    
    ke_hash_map m;
    ASSERT_EQ(ke_hash_map_init(&m, 16, &fa), KE_ERROR_OUT_OF_MEMORY);
}

// --- Destroy Tests ---

TEST(HashMapDestroyTest, Destroy_NullMap_DoesNotCrash) {
    ke_hash_map_destroy(nullptr);
    SUCCEED();
}

TEST(HashMapDestroyTest, Destroy_NullEntries_DoesNotCrash) {
    ke_hash_map m;
    m.entries = nullptr;
    m.allocator = nullptr;
    ke_hash_map_destroy(&m);
    SUCCEED();
}

// --- Insert Tests ---

TEST_F(HashMapTest, Insert_NullMap_ReturnsInvalidArgument) {
    int v = 1;
    ASSERT_EQ(ke_hash_map_insert(nullptr, 1, &v), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(HashMapTest, Insert_NullEntries_ReturnsInvalidArgument) {
    int v = 1;
    ke_hash_map_destroy(&map);
    map_initialized = false;
    ASSERT_EQ(ke_hash_map_insert(&map, 1, &v), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(HashMapTest, Insert_NewKey_ReturnsOk) {
    int v = 1;
    ASSERT_EQ(ke_hash_map_insert(&map, 1, &v), KE_OK);
}

TEST_F(HashMapTest, Insert_DuplicateKey_ReturnsOk) {
    int v1 = 1, v2 = 2;
    ke_hash_map_insert(&map, 1, &v1);
    ASSERT_EQ(ke_hash_map_insert(&map, 1, &v2), KE_OK);
}

TEST_F(HashMapTest, Insert_IncrementsSizeForNewKey) {
    int v = 1;
    size_t initial_size = map.size;
    ke_hash_map_insert(&map, 1, &v);
    ASSERT_EQ(map.size, initial_size + 1);
}

TEST_F(HashMapTest, Insert_DoesNotIncrementSizeForDuplicateKey) {
    int v1 = 1, v2 = 2;
    ke_hash_map_insert(&map, 1, &v1);
    size_t size_after_first = map.size;
    ke_hash_map_insert(&map, 1, &v2);
    ASSERT_EQ(map.size, size_after_first);
}

// --- Get Tests ---

TEST_F(HashMapTest, Get_ExistingKey_ReturnsCorrectValue) {
    int v = 42;
    ke_hash_map_insert(&map, 123, &v);
    ASSERT_EQ(ke_hash_map_get(&map, 123), &v);
}

TEST_F(HashMapTest, Get_NonExistingKey_ReturnsNull) {
    ASSERT_EQ(ke_hash_map_get(&map, 999), nullptr);
}

TEST_F(HashMapTest, Get_AfterDuplicateInsert_ReturnsLatestValue) {
    int v1 = 1, v2 = 2;
    ke_hash_map_insert(&map, 1, &v1);
    ke_hash_map_insert(&map, 1, &v2);
    ASSERT_EQ(ke_hash_map_get(&map, 1), &v2);
}

TEST_F(HashMapTest, Get_NullEntries_ReturnsNull) {
    ke_hash_map_destroy(&map);
    map_initialized = false;
    ASSERT_EQ(ke_hash_map_get(&map, 1), nullptr);
}

TEST_F(HashMapTest, Get_CapacityZero_ReturnsNull) {
    map.capacity = 0;
    ASSERT_EQ(ke_hash_map_get(&map, 1), nullptr);
}

// --- Rehash and Probing Tests ---

TEST_F(HashMapTest, Rehash_TriggersWhenLoadFactorExceeded) {
    // Capacity 16, load factor 0.7 -> 11.2 -> 12 elements should trigger rehash
    int values[12];
    size_t initial_cap = map.capacity;
    for (int i = 0; i < 12; ++i) {
        ke_hash_map_insert(&map, i + 1, &values[i]);
    }
    ASSERT_GT(map.capacity, initial_cap);
}

TEST_F(HashMapTest, Get_WorksAfterRehash) {
    int values[12];
    for (int i = 0; i < 12; ++i) {
        ke_hash_map_insert(&map, i + 1, &values[i]);
    }
    ASSERT_EQ(ke_hash_map_get(&map, 1), &values[0]);
}

TEST_F(HashMapTest, Get_WorksWithCollisionLinearProbing) {
    // Force collision: 1 % 16 = 1, 17 % 16 = 1
    int v1 = 1, v2 = 2;
    ke_hash_map_insert(&map, 1, &v1);
    ke_hash_map_insert(&map, 17, &v2);
    ASSERT_EQ(ke_hash_map_get(&map, 17), &v2);
}

TEST_F(HashMapTest, Get_FullLoopBreak_ReturnsNull) {
    // Manually fill map to 100% without rehashing to test the loop break in get
    // This is a bit white-box
    ke_hash_map_destroy(&map);
    ke_hash_map_init(&map, 4, alloc);
    map_initialized = true;
    
    int v = 1;
    // Keys that probe to 0, 1, 2, 3
    map.entries[0].key = 4; map.entries[0].value = &v;
    map.entries[1].key = 1; map.entries[1].value = &v;
    map.entries[2].key = 2; map.entries[2].value = &v;
    map.entries[3].key = 3; map.entries[3].value = &v;
    map.size = 4;
    
    // Search for key that is not there, and all slots are full
    ASSERT_EQ(ke_hash_map_get(&map, 5), nullptr);
}

TEST(HashMapRehashTest, Rehash_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.realloc = fail_realloc;
    fa.free = fail_free;
    fa.destroy = fail_destroy;
    
    ke_hash_map m;
    m.capacity = 2;
    m.size = 0;
    m.allocator = &fa;
    // Normally entries would be allocated, but we'll mock it
    ke_hash_map_entry mock_entries[2] = {{0,0}, {0,0}};
    m.entries = mock_entries;
    
    int v = 1;
    // Load factor 0.7 * 2 = 1.4 -> 2 elements trigger rehash
    ke_hash_map_insert(&m, 1, &v);
    ASSERT_EQ(ke_hash_map_insert(&m, 2, &v), KE_ERROR_OUT_OF_MEMORY);
}

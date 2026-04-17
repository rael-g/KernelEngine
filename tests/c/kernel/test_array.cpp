#include <gtest/gtest.h>
#include <kernel_engine/kernel/common/array.h>
#include <kernel_engine/kernel/context/allocator.h>

class ArrayTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_array arr;
    bool arr_initialized = false;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_array_init(&arr, 4, alloc);
        ASSERT_EQ(res, KE_OK);
        arr_initialized = true;
    }

    void TearDown() override {
        if (arr_initialized) {
            ke_array_destroy(&arr);
        }
        if (alloc) {
            alloc->destroy(alloc);
        }
    }
};

// --- Initialization Tests ---

TEST(ArrayInitTest, Init_NullArray_ReturnsInvalidArgument) {
    ke_allocator* a = ke_allocator_malloc_create();
    ASSERT_EQ(ke_array_init(nullptr, 4, a), KE_ERROR_INVALID_ARGUMENT);
    a->destroy(a);
}

TEST(ArrayInitTest, Init_NullAllocator_ReturnsInvalidArgument) {
    ke_array a;
    ASSERT_EQ(ke_array_init(&a, 4, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

static void* fail_alloc(ke_allocator* alloc, size_t size, size_t alignment) { return nullptr; }
static void* fail_realloc(ke_allocator* alloc, void* ptr, size_t size) { return nullptr; }
static void fail_free(ke_allocator* alloc, void* ptr) {}
static void fail_destroy(ke_allocator* alloc) {}

TEST(ArrayInitTest, Init_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.realloc = fail_realloc;
    fa.free = fail_free;
    fa.destroy = fail_destroy;
    
    ke_array a;
    ASSERT_EQ(ke_array_init(&a, 4, &fa), KE_ERROR_OUT_OF_MEMORY);
}

TEST_F(ArrayTest, Init_SetsSizeToZero) {
    ASSERT_EQ(arr.size, 0);
}

TEST_F(ArrayTest, Init_SetsCapacity) {
    ASSERT_EQ(arr.capacity, 4);
}

// --- Destroy Tests ---

TEST(ArrayDestroyTest, Destroy_NullArray_DoesNotCrash) {
    ke_array_destroy(nullptr);
    SUCCEED();
}

TEST_F(ArrayTest, Destroy_ClearsSize) {
    ke_array_destroy(&arr);
    arr_initialized = false;
    ASSERT_EQ(arr.size, 0);
}

TEST_F(ArrayTest, Destroy_ClearsCapacity) {
    ke_array_destroy(&arr);
    arr_initialized = false;
    ASSERT_EQ(arr.capacity, 0);
}

TEST_F(ArrayTest, Destroy_ClearsData) {
    ke_array_destroy(&arr);
    arr_initialized = false;
    ASSERT_EQ(arr.data, nullptr);
}

// --- Push Tests ---

TEST_F(ArrayTest, Push_NullArray_ReturnsInvalidArgument) {
    int v = 1;
    ASSERT_EQ(ke_array_push(nullptr, &v), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(ArrayTest, Push_FirstValue_ReturnsOk) {
    int v = 1;
    ASSERT_EQ(ke_array_push(&arr, &v), KE_OK);
}

TEST_F(ArrayTest, Push_IncrementsSize) {
    int v = 1;
    ke_array_push(&arr, &v);
    ASSERT_EQ(arr.size, 1);
}

TEST_F(ArrayTest, Push_StoresCorrectValue) {
    int v = 42;
    ke_array_push(&arr, &v);
    ASSERT_EQ(arr.data[0], &v);
}

TEST_F(ArrayTest, Push_MultipleValues_OrderPreserved) {
    int v1 = 1, v2 = 2;
    ke_array_push(&arr, &v1);
    ke_array_push(&arr, &v2);
    ASSERT_EQ(arr.data[1], &v2);
}

TEST_F(ArrayTest, Push_TriggerResize_ReturnsOk) {
    int values[5] = {1, 2, 3, 4, 5};
    for (int i = 0; i < 4; ++i) ke_array_push(&arr, &values[i]);
    // Next push triggers resize
    ASSERT_EQ(ke_array_push(&arr, &values[4]), KE_OK);
}

TEST_F(ArrayTest, Push_TriggerResize_IncrementsCapacity) {
    int values[5] = {1, 2, 3, 4, 5};
    size_t initial_cap = arr.capacity;
    for (int i = 0; i < 5; ++i) ke_array_push(&arr, &values[i]);
    ASSERT_GT(arr.capacity, initial_cap);
}

TEST_F(ArrayTest, Push_TriggerResize_DataPreserved) {
    int values[5] = {1, 2, 3, 4, 5};
    for (int i = 0; i < 5; ++i) ke_array_push(&arr, &values[i]);
    ASSERT_EQ(arr.data[0], &values[0]);
}

TEST(ArrayPushResizeTest, Push_ResizeFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = ke_allocator_malloc_create()->alloc; // Use real alloc for initial
    fa.realloc = fail_realloc;
    fa.free = fail_free;
    fa.destroy = fail_destroy;
    
    ke_array a;
    ke_array_init(&a, 1, &fa);
    
    int v1 = 1, v2 = 2;
    ke_array_push(&a, &v1);
    // Next push triggers resize and fails
    ASSERT_EQ(ke_array_push(&a, &v2), KE_ERROR_OUT_OF_MEMORY);
    
    // Clean up manually since we hijacked the allocator
    ke_allocator* real_alloc = ke_allocator_malloc_create();
    real_alloc->free(real_alloc, a.data);
    real_alloc->destroy(real_alloc);
}

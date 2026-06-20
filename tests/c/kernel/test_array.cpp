#include <gtest/gtest.h>
#include <kernel_engine/kernel/common/array.h>
#include <kernel_engine/allocator/allocator.h>

class ArrayTest : public ::testing::Test {
protected:
    ke_array arr;
    bool arr_initialized = false;

    void SetUp() override {
        ke_result res = ke_array_init(&arr, 4);
        ASSERT_EQ(res, KE_OK);
        arr_initialized = true;
    }

    void TearDown() override {
        if (arr_initialized) {
            ke_array_destroy(&arr);
        }
    }
};

// --- Initialization Tests ---

TEST(ArrayInitTest, Init_NullArray_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_array_init(nullptr, 4), KE_ERROR);
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
    ASSERT_EQ(ke_array_push(nullptr, &v), KE_ERROR);
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

TEST_F(ArrayTest, Pop_ReturnsLastValue) {
    int v1 = 1, v2 = 2;
    ke_array_push(&arr, &v1);
    ke_array_push(&arr, &v2);
    ASSERT_EQ(ke_array_pop(&arr), &v2);
    ASSERT_EQ(arr.size, 1u);
}

TEST_F(ArrayTest, Pop_NullArray_ReturnsNull) {
    ASSERT_EQ(ke_array_pop(nullptr), nullptr);
}

TEST_F(ArrayTest, Pop_EmptyArray_ReturnsNull) {
    ASSERT_EQ(ke_array_pop(&arr), nullptr);
}

TEST_F(ArrayTest, Clear_ResetsSize) {
    int v = 1;
    ke_array_push(&arr, &v);
    ke_array_clear(&arr);
    ASSERT_EQ(arr.size, 0u);
}

TEST_F(ArrayTest, Clear_NullArray_IsSafe) {
    ke_array_clear(nullptr);
    SUCCEED();
}

#include <gtest/gtest.h>
#include <kernel_engine/kernel/input/input.h>
#include <kernel_engine/kernel/context/allocator.h>

class InputTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_input* input = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_input_create(alloc, nullptr, &input);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (input) input->destroy(input);
        if (alloc) alloc->destroy(alloc);
    }
};

// --- Creation Tests ---

TEST(InputInitTest, Create_NullOutInput_ReturnsInvalidArgument) {
    ke_allocator* a = ke_allocator_malloc_create();
    ASSERT_EQ(ke_input_create(a, nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
    a->destroy(a);
}

TEST(InputInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_input* i = nullptr;
    ASSERT_EQ(ke_input_create(nullptr, nullptr, &i), KE_ERROR_INVALID_ARGUMENT);
}

static void* fail_alloc(ke_allocator* alloc, size_t size, size_t alignment) { return nullptr; }
static void fail_free(ke_allocator* alloc, void* ptr) {}

TEST(InputInitTest, Create_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.free = fail_free;
    ke_input* i = nullptr;
    ASSERT_EQ(ke_input_create(&fa, nullptr, &i), KE_ERROR_OUT_OF_MEMORY);
}

// --- Destroy Tests ---

TEST(InputDestroyTest, Destroy_NullInput_DoesNotCrash) {
    ke_allocator* a = ke_allocator_malloc_create();
    ke_input* i = nullptr;
    ke_input_create(a, nullptr, &i);
    auto destroy_fn = i->destroy;
    i->destroy(i);
    destroy_fn(nullptr);
    a->destroy(a);
    SUCCEED();
}

TEST_F(InputTest, Destroy_WorksNormally) {
    input->destroy(input);
    input = nullptr;
    SUCCEED();
}

// --- Update and State Tests ---

TEST_F(InputTest, Update_NullSelf_ReturnsInvalidArgument) {
    auto update_fn = input->update;
    ASSERT_EQ(update_fn(nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(InputTest, KeyPressed_IsDetected) {
    input->update(input);        // clear previous frame
    input->on_key(input, 65, 1); // 'A' press event arrives
    ASSERT_TRUE(input->is_key_pressed(input, 65));
}

TEST_F(InputTest, Snapshot_KeyIsCaptured) {
    input->on_key(input, 65, 1);
    ke_input_snapshot snapshot;
    input->get_snapshot(input, &snapshot);
    
    int word = 65 / 64;
    uint64_t bit = (1ULL << (65 % 64));
    ASSERT_TRUE(snapshot.keys_pressed[word] & bit);
}

TEST_F(InputTest, MouseMove_IsCaptured) {
    input->on_mouse_move(input, 100.0f, 200.0f);
    ke_input_snapshot snapshot;
    input->get_snapshot(input, &snapshot);
    ASSERT_FLOAT_EQ(snapshot.mouse_x, 100.0f);
    ASSERT_FLOAT_EQ(snapshot.mouse_y, 200.0f);
}

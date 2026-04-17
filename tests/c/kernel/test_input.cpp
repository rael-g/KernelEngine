#include <gtest/gtest.h>
#include <kernel_engine/kernel/input/input.h>
#include <kernel_engine/kernel/input/input_messages.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <kernel_engine/kernel/context/allocator.h>

class InputTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_message_pipe* pipe = nullptr;
    ke_input* input = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_message_pipe_create(alloc, nullptr, &pipe);
        ASSERT_EQ(res, KE_OK);
        res = ke_input_create(alloc, nullptr, pipe, &input);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (input) input->destroy(input);
        if (pipe) pipe->destroy(pipe);
        if (alloc) alloc->destroy(alloc);
    }
};

// --- Creation Tests ---

TEST(InputInitTest, Create_NullOutInput_ReturnsInvalidArgument) {
    ke_allocator* a = ke_allocator_malloc_create();
    ASSERT_EQ(ke_input_create(a, nullptr, nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
    a->destroy(a);
}

TEST(InputInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_input* i = nullptr;
    ASSERT_EQ(ke_input_create(nullptr, nullptr, nullptr, &i), KE_ERROR_INVALID_ARGUMENT);
}

static void* fail_alloc(ke_allocator* alloc, size_t size, size_t alignment) { return nullptr; }
static void fail_free(ke_allocator* alloc, void* ptr) {}

TEST(InputInitTest, Create_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.free = fail_free;
    ke_input* i = nullptr;
    ASSERT_EQ(ke_input_create(&fa, nullptr, nullptr, &i), KE_ERROR_OUT_OF_MEMORY);
}

// --- Destroy Tests ---

TEST(InputDestroyTest, Destroy_NullInput_DoesNotCrash) {
    ke_allocator* a = ke_allocator_malloc_create();
    ke_input* i = nullptr;
    ke_input_create(a, nullptr, nullptr, &i);
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
    // We need to call the static input_update via the function pointer
    auto update_fn = input->update;
    ASSERT_EQ(update_fn(nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(InputTest, Update_NullPipe_ReturnsOk) {
    input->message_pipe = nullptr;
    ASSERT_EQ(input->update(input), KE_OK);
}

TEST_F(InputTest, KeyPressed_IsDetected) {
    ke_msg_key_event ev = { 65, 1 }; // 'A' press
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    input->update(input);
    ASSERT_TRUE(input->is_key_pressed(input, 65));
}

TEST_F(InputTest, KeyPressed_ResetsAfterUpdate) {
    ke_msg_key_event ev = { 65, 1 };
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    input->update(input);
    input->update(input); // Second update should clear 'pressed'
    ASSERT_FALSE(input->is_key_pressed(input, 65));
}

TEST_F(InputTest, KeyReleased_IsDetected) {
    // Press then release
    ke_msg_key_event ev = { 65, 1 };
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    input->update(input);
    
    ev.action = 0; // release
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    input->update(input);
    
    ASSERT_TRUE(input->is_key_released(input, 65));
}

TEST_F(InputTest, KeyDown_IsDetected) {
    ke_msg_key_event ev = { 65, 1 };
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    input->update(input);
    ASSERT_TRUE(input->is_key_down(input, 65));
}

TEST_F(InputTest, KeyDown_PersistsUntilRelease) {
    ke_msg_key_event ev = { 65, 1 };
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    input->update(input);
    input->update(input);
    ASSERT_TRUE(input->is_key_down(input, 65));
}

TEST_F(InputTest, KeyDown_ClearsAfterRelease) {
    ke_msg_key_event ev = { 65, 1 };
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    input->update(input);
    
    ev.action = 0;
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    input->update(input);
    
    ASSERT_FALSE(input->is_key_down(input, 65));
}

TEST_F(InputTest, Update_IgnoresInvalidKey_Low) {
    ke_msg_key_event ev = { -1, 1 };
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    ASSERT_EQ(input->update(input), KE_OK);
}

TEST_F(InputTest, Update_IgnoresInvalidKey_High) {
    ke_msg_key_event ev = { 9999, 1 };
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    ASSERT_EQ(input->update(input), KE_OK);
}

TEST_F(InputTest, IsKeyPressed_NullSelf_ReturnsFalse) {
    ASSERT_FALSE(input->is_key_pressed(nullptr, 65));
}

TEST_F(InputTest, IsKeyPressed_InvalidKey_ReturnsFalse) {
    ASSERT_FALSE(input->is_key_pressed(input, -1));
}

TEST_F(InputTest, IsKeyReleased_NullSelf_ReturnsFalse) {
    ASSERT_FALSE(input->is_key_released(nullptr, 65));
}

TEST_F(InputTest, IsKeyReleased_InvalidKey_ReturnsFalse) {
    ASSERT_FALSE(input->is_key_released(input, 999));
}

TEST_F(InputTest, IsKeyDown_NullSelf_ReturnsFalse) {
    ASSERT_FALSE(input->is_key_down(nullptr, 65));
}

TEST_F(InputTest, IsKeyDown_InvalidKey_ReturnsFalse) {
    ASSERT_FALSE(input->is_key_down(input, 513));
}

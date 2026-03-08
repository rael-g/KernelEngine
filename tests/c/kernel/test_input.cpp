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
        if (input) {
            input->destroy(input);
        }
        if (pipe) {
            pipe->destroy(pipe);
        }
        if (alloc) {
            alloc->destroy(alloc);
        }
    }
};

TEST_F(InputTest, KeyboardState) {
    ke_msg_key_event ev;
    ev.key = 65; // 'A'
    ev.action = 1; // Press
    
    // Broadcast message to pipe
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    
    // Update input (reads pipe)
    input->update(input);
    
    // Check state
    ASSERT_TRUE(input->is_key_down(input, 65));
    ASSERT_TRUE(input->is_key_pressed(input, 65));
    
    // Release
    ev.action = 0; // Release
    pipe->broadcast(pipe, KE_MSG_KEY_EVENT, &ev, sizeof(ev));
    input->update(input);
    
    ASSERT_FALSE(input->is_key_down(input, 65));
    ASSERT_TRUE(input->is_key_released(input, 65));
}

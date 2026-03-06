#include <gtest/gtest.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <kernel_engine/kernel/context/allocator.h>

class MessagePipeTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_message_pipe* pipe = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_message_pipe_create(alloc, nullptr, &pipe);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (pipe) {
            pipe->destroy(pipe);
        }
        if (alloc) {
            alloc->destroy(alloc);
        }
    }
};

TEST_F(MessagePipeTest, BroadcastAndReceive) {
    ke_message_pipe* reader = nullptr;
    ke_result res = pipe->create_reader(pipe, &reader);
    ASSERT_EQ(res, KE_OK);
    
    int msg_data = 1234;
    pipe->broadcast(pipe, 1, &msg_data, sizeof(int));
    
    int received = 0;
    // Current implementation doesn't need pump to move to readers as create_reader returns self
    bool ok = reader->try_receive(reader, 1, &received, sizeof(int));
    ASSERT_TRUE(ok);
    ASSERT_EQ(received, 1234);
    
    // reader shouldn't be destroyed separately if it's just 'self', 
    // but the API has a destroy function. In this impl, it would destroy the whole pipe.
    // So we don't call reader->destroy(reader) here if reader == pipe.
}

TEST_F(MessagePipeTest, PumpResets) {
    int msg_data = 555;
    pipe->broadcast(pipe, 1, &msg_data, sizeof(int));
    pipe->pump(pipe);
    
    int v1 = 0;
    ASSERT_FALSE(pipe->try_receive(pipe, 1, &v1, sizeof(int)));
}

TEST_F(MessagePipeTest, NoMessages) {
    int val;
    bool ok = pipe->try_receive(pipe, 1, &val, sizeof(int));
    ASSERT_FALSE(ok);
}

TEST_F(MessagePipeTest, FilterByMessageId) {
    int d1 = 10, d2 = 20;
    pipe->broadcast(pipe, 100, &d1, sizeof(int));
    pipe->broadcast(pipe, 200, &d2, sizeof(int));
    
    int val = 0;
    // Receive 100 first (order of broadcast)
    ASSERT_TRUE(pipe->try_receive(pipe, 100, &val, sizeof(int)));
    ASSERT_EQ(val, 10);
    // Then 200
    ASSERT_TRUE(pipe->try_receive(pipe, 200, &val, sizeof(int)));
    ASSERT_EQ(val, 20);
}

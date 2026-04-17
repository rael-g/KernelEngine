#include <gtest/gtest.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <string.h>

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
        if (pipe) pipe->destroy(pipe);
        if (alloc) alloc->destroy(alloc);
    }
};

// --- Creation Tests ---

TEST(MessagePipeInitTest, Create_NullOutPipe_ReturnsInvalidArgument) {
    ke_allocator* a = ke_allocator_malloc_create();
    ASSERT_EQ(ke_message_pipe_create(a, nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
    a->destroy(a);
}

TEST(MessagePipeInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_message_pipe* p = nullptr;
    ASSERT_EQ(ke_message_pipe_create(nullptr, nullptr, &p), KE_ERROR_INVALID_ARGUMENT);
}

static void* fail_alloc(ke_allocator* alloc, size_t size, size_t alignment) { return nullptr; }
static void fail_free(ke_allocator* alloc, void* ptr) {}

TEST(MessagePipeInitTest, Create_AllocationFailure_ReturnsOutOfMemory) {
    ke_allocator fa;
    fa.alloc = fail_alloc;
    fa.free = fail_free;
    ke_message_pipe* p = nullptr;
    ASSERT_EQ(ke_message_pipe_create(&fa, nullptr, &p), KE_ERROR_OUT_OF_MEMORY);
}

// --- Destroy Tests ---

TEST_F(MessagePipeTest, Destroy_NullPipe_DoesNotCrash) {
    auto destroy_fn = pipe->destroy;
    destroy_fn(nullptr);
    SUCCEED();
}

// --- Broadcast Tests ---

TEST_F(MessagePipeTest, Broadcast_NullSelf_ReturnsInvalidArgument) {
    auto broadcast_fn = pipe->broadcast;
    ASSERT_EQ(broadcast_fn(nullptr, 1, nullptr, 0), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(MessagePipeTest, Broadcast_Success_ReturnsOk) {
    int val = 123;
    ASSERT_EQ(pipe->broadcast(pipe, 1, &val, sizeof(val)), KE_OK);
}

TEST_F(MessagePipeTest, Broadcast_DataPoolFull_ReturnsError) {
    // Pool size is 128KB
    std::vector<uint8_t> large_data(128 * 1024 + 1);
    ASSERT_EQ(pipe->broadcast(pipe, 1, large_data.data(), large_data.size()), KE_ERROR);
}

TEST_F(MessagePipeTest, Broadcast_MaxMessagesExceeded_ReturnsError) {
    // Max count is 1024
    int val = 1;
    for(int i=0; i<1024; ++i) {
        pipe->broadcast(pipe, 1, &val, sizeof(val));
    }
    ASSERT_EQ(pipe->broadcast(pipe, 1, &val, sizeof(val)), KE_ERROR);
}

// --- Receive Tests ---

TEST_F(MessagePipeTest, TryReceive_NullSelf_ReturnsFalse) {
    auto receive_fn = pipe->try_receive;
    int val;
    ASSERT_FALSE(receive_fn(nullptr, 1, &val, sizeof(val)));
}

TEST_F(MessagePipeTest, TryReceive_EmptyPipe_ReturnsFalse) {
    int val;
    ASSERT_FALSE(pipe->try_receive(pipe, 1, &val, sizeof(val)));
}

TEST_F(MessagePipeTest, TryReceive_MatchesId_ReturnsTrue) {
    int send = 123, recv = 0;
    pipe->broadcast(pipe, 10, &send, sizeof(send));
    ASSERT_TRUE(pipe->try_receive(pipe, 10, &recv, sizeof(recv)));
}

TEST_F(MessagePipeTest, TryReceive_MatchesId_ReturnsCorrectData) {
    int send = 123, recv = 0;
    pipe->broadcast(pipe, 10, &send, sizeof(send));
    pipe->try_receive(pipe, 10, &recv, sizeof(recv));
    ASSERT_EQ(recv, 123);
}

TEST_F(MessagePipeTest, TryReceive_WildcardId_ReturnsTrue) {
    int send = 123, recv = 0;
    pipe->broadcast(pipe, 10, &send, sizeof(send));
    // ID 0 matches anything
    ASSERT_TRUE(pipe->try_receive(pipe, 0, &recv, sizeof(recv)));
}

TEST_F(MessagePipeTest, TryReceive_MismatchedId_ReturnsFalse) {
    int send = 123, recv = 0;
    pipe->broadcast(pipe, 10, &send, sizeof(send));
    ASSERT_FALSE(pipe->try_receive(pipe, 20, &recv, sizeof(recv)));
}

TEST_F(MessagePipeTest, TryReceive_BufferTooSmall_DoesNotCopy) {
    int send = 123, recv = 0;
    pipe->broadcast(pipe, 10, &send, sizeof(send));
    // Size is 4, max_size 2
    pipe->try_receive(pipe, 10, &recv, 2);
    ASSERT_EQ(recv, 0);
}

// --- Reader and Pump Tests ---

TEST_F(MessagePipeTest, CreateReader_ReturnsSameInstance) {
    ke_message_pipe* reader = nullptr;
    pipe->create_reader(pipe, &reader);
    ASSERT_EQ(reader, pipe);
}

TEST_F(MessagePipeTest, CreateReader_NullSelf_ReturnsInvalidArgument) {
    ke_message_pipe* reader = nullptr;
    auto create_reader_fn = pipe->create_reader;
    ASSERT_EQ(create_reader_fn(nullptr, &reader), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(MessagePipeTest, CreateReader_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(pipe->create_reader(pipe, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(MessagePipeTest, Pump_NullSelf_ReturnsInvalidArgument) {
    auto pump_fn = pipe->pump;
    ASSERT_EQ(pump_fn(nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(MessagePipeTest, Pump_ClearsMessages) {
    int val = 1;
    pipe->broadcast(pipe, 1, &val, sizeof(val));
    pipe->pump(pipe);
    ASSERT_FALSE(pipe->try_receive(pipe, 1, &val, sizeof(val)));
}

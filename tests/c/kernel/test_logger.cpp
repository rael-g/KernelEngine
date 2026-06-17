#include <gtest/gtest.h>
#include <kernel_engine/logger/logger.h>
#include <stdio.h>
#include <string.h>

namespace {
// Inline console sink for tests (the kernel no longer ships one; see W.16).
void test_console_sink_log(ke_logger_sink *, const ke_log_event *event)
{
    fprintf(stderr, "[%s] %s: %s\n",
            ke_log_level_to_string(event->level),
            event->tag     ? event->tag     : "",
            event->message ? event->message : "");
    fflush(stderr);
}
ke_logger_sink test_console_sink(ke_log_level min_level)
{
    ke_logger_sink s{};
    s.min_level = (int32_t)min_level;
    s.log       = test_console_sink_log;
    return s;
}
} // namespace

class LoggerTest : public ::testing::Test {
protected:
    ke_logger* logger = nullptr;

    void SetUp() override {
        ke_result res = ke_logger_create(&logger, NULL);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (logger) logger->destroy(logger);
    }
};

// --- Creation Tests ---

TEST(LoggerInitTest, Create_NullOutLogger_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_logger_create(nullptr, NULL), KE_ERROR);
}

// --- Destroy Tests ---

TEST_F(LoggerTest, Destroy_NullLogger_DoesNotCrash) {
    auto destroy_fn = logger->destroy;
    destroy_fn(nullptr);
    SUCCEED();
}

TEST_F(LoggerTest, Destroy_WithSinks_Works) {
    ke_logger_sink sink = test_console_sink(KE_LOG_LEVEL_INFO);
    logger->add_sink(logger, sink, NULL);
    logger->destroy(logger);
    logger = nullptr;
    SUCCEED();
}

// --- Log and Sink Tests ---

TEST_F(LoggerTest, Log_NullSelf_DoesNotCrash) {
    ke_log_event ev = { KE_LOG_LEVEL_INFO, "TAG", "Msg" };
    auto log_fn = logger->log;
    log_fn(nullptr, &ev);
    SUCCEED();
}

TEST_F(LoggerTest, Log_NullEvent_DoesNotCrash) {
    logger->log(logger, nullptr);
    SUCCEED();
}

TEST_F(LoggerTest, AddSink_NullSelf_ReturnsInvalidArgument) {
    ke_logger_sink sink = test_console_sink(KE_LOG_LEVEL_INFO);
    auto add_sink_fn = logger->add_sink;
    ASSERT_EQ(add_sink_fn(nullptr, sink, nullptr), KE_ERROR);
}

static void mock_sink_log(ke_logger_sink* self, const ke_log_event* event) {
    int* count = (int*)self->handle;
    (*count)++;
}

TEST_F(LoggerTest, Log_CallsSink_WhenLevelMatches) {
    int call_count = 0;
    ke_logger_sink sink;
    sink.handle = &call_count;
    sink.min_level = KE_LOG_LEVEL_INFO;
    sink.log = mock_sink_log;
    sink.destroy = nullptr;
    
    logger->add_sink(logger, sink, NULL);
    
    ke_log_event ev = { KE_LOG_LEVEL_INFO, "TEST", "Message" };
    logger->log(logger, &ev);
    
    ASSERT_EQ(call_count, 1);
}

TEST_F(LoggerTest, Log_DoesNotCallSink_WhenLevelIsLower) {
    int call_count = 0;
    ke_logger_sink sink;
    sink.handle = &call_count;
    sink.min_level = KE_LOG_LEVEL_ERROR;
    sink.log = mock_sink_log;
    sink.destroy = nullptr;
    
    logger->add_sink(logger, sink, NULL);
    
    ke_log_event ev = { KE_LOG_LEVEL_INFO, "TEST", "Message" };
    logger->log(logger, &ev);
    
    ASSERT_EQ(call_count, 0);
}

TEST_F(LoggerTest, Log_SkipsSink_WhenLogFnIsNull) {
    ke_logger_sink sink;
    sink.handle = nullptr;
    sink.min_level = KE_LOG_LEVEL_TRACE;
    sink.log = nullptr; // Null log function
    sink.destroy = nullptr;
    
    logger->add_sink(logger, sink, NULL);
    
    ke_log_event ev = { KE_LOG_LEVEL_INFO, "TEST", "Message" };
    logger->log(logger, &ev);
    SUCCEED();
}

TEST_F(LoggerTest, ConsoleSink_NullTagAndMessage_DoesNotCrash) {
    ke_logger_sink sink = test_console_sink(KE_LOG_LEVEL_TRACE);
    logger->add_sink(logger, sink, NULL);
    
    ke_log_event ev = { KE_LOG_LEVEL_INFO, nullptr, nullptr };
    logger->log(logger, &ev);
    SUCCEED();
}

static void mock_sink_destroy(ke_logger_sink* self) {
    int* count = (int*)self->handle;
    (*count)++;
}

TEST_F(LoggerTest, Destroy_CallsSinkDestroy) {
    int destroy_count = 0;
    ke_logger_sink sink;
    sink.handle = &destroy_count;
    sink.log = nullptr;
    sink.destroy = mock_sink_destroy;
    
    logger->add_sink(logger, sink, NULL);
    logger->destroy(logger);
    logger = nullptr;
    
    ASSERT_EQ(destroy_count, 1);
}

// --- Helper Tests ---

TEST(LoggerHelperTest, LevelToString_ValidLevels) {
    ASSERT_STREQ(ke_log_level_to_string(KE_LOG_LEVEL_INFO), "INFO");
}

TEST(LoggerHelperTest, LevelToString_InvalidLevel_Low) {
    ASSERT_STREQ(ke_log_level_to_string(-1), "UNKNOWN");
}

TEST(LoggerHelperTest, LevelToString_InvalidLevel_High) {
    ASSERT_STREQ(ke_log_level_to_string(6), "UNKNOWN");
}

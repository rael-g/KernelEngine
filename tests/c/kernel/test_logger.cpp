#include <gtest/gtest.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/logger/console_sink.h>
#include <kernel_engine/kernel/context/allocator.h>

class LoggerTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_logger* logger = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ASSERT_NE(alloc, nullptr);
        ke_result res = ke_logger_create(alloc, &logger);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (logger) {
            logger->destroy(logger);
        }
        if (alloc) {
            alloc->destroy(alloc);
        }
    }
};

TEST_F(LoggerTest, BasicLogging) {
    ke_log_event ev;
    ev.level = KE_LOG_LEVEL_INFO;
    ev.tag = "TEST";
    ev.message = "Test message";
    
    // Should not crash even without sinks
    logger->log(logger, &ev);
}

TEST_F(LoggerTest, ConsoleSink) {
    ke_logger_sink sink = ke_console_sink_create(KE_LOG_LEVEL_TRACE);
    
    ke_result res = logger->add_sink(logger, sink);
    ASSERT_EQ(res, KE_OK);
    
    ke_log_event ev;
    ev.level = KE_LOG_LEVEL_INFO;
    ev.tag = "TEST";
    ev.message = "Testing console sink";
    
    logger->log(logger, &ev);
}

TEST_F(LoggerTest, LevelFiltering) {
    // Sink only accepts ERROR (value 4)
    ke_logger_sink sink = ke_console_sink_create(KE_LOG_LEVEL_ERROR);
    
    logger->add_sink(logger, sink);
    
    ke_log_event ev;
    ev.tag = "TEST";
    
    // This should be filtered out
    ev.level = KE_LOG_LEVEL_INFO;
    ev.message = "This should not be logged";
    logger->log(logger, &ev);
    
    // This should pass
    ev.level = KE_LOG_LEVEL_ERROR;
    ev.message = "This SHOULD be logged";
    logger->log(logger, &ev);
}

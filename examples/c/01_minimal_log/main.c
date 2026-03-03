#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/engine/engine.h>
#include <kernel_engine/core/logger/logger.h>
#include <kernel_engine/core/messaging/message_pipe.h>
#include <stdio.h>
#include <stdlib.h>

static void app_console_sink(ke_logger_sink *self, int level, const char *tag, const char *message)
{
    (void)self;
    printf("[%s][%s] %s\n", tag, ke_log_level_to_string(level), message);
}


int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    printf("--- KernelEngine Minimal Log Example (Full IoC) ---\n");

    ke_allocator *root_alloc = ke_allocator_malloc_create();
    if (!root_alloc)
    {
        return 1;
    }

    ke_descriptor bootstrap_desc = {.allocator = root_alloc, .logger = NULL, .message_pipe = NULL};

    ke_logger *logger = NULL;
    if (ke_logger_create(&bootstrap_desc, &logger) == KE_OK)
    {
        ke_logger_sink sink = {.handle = NULL, .log = app_console_sink, .destroy = NULL};
        logger->add_sink(logger, sink);
    }

    bootstrap_desc.logger = logger;
    ke_engine *engine = NULL;
    if (ke_engine_create(&bootstrap_desc, &engine) == KE_OK)
    {
        engine->initialize(engine);

        for (int i = 0; i < 3; ++i)
        {
            if (logger)
            {
                char buf[32];
                snprintf(buf, sizeof(buf), "Manual Tick %d", i + 1);
                logger->log(logger, KE_LOG_LEVEL_DEBUG, "app", buf);
            }
            engine->tick(engine, NULL);
        }
    }

    if (engine)
    {
        engine->destroy(engine);
    }
    if (logger)
    {
        logger->destroy(logger);
    }
    root_alloc->destroy(root_alloc);

    printf("--- Shutdown Complete ---\n");
    return 0;
}

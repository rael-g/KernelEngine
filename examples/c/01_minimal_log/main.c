#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <stdio.h>

static void app_console_sink(ke_logger_sink *self, const ke_log_event *ev)
{
    (void)self;
    printf("[%s] %s\n", ev->tag, ev->message);
}

int main(void)
{
    printf("--- KernelEngine C Minimal Log Demo ---\n");

    ke_allocator *alloc = ke_allocator_malloc_create();
    if (!alloc) return 1;

    ke_descriptor desc = {
        .allocator = alloc,
        .logger = NULL,
        .message_pipe = NULL
    };

    ke_logger *logger = NULL;
    ke_result res = ke_logger_create(&desc, &logger);

    if (res == KE_OK)
    {
        ke_logger_sink sink = {.handle = NULL, .log = app_console_sink, .destroy = NULL};
        logger->add_sink(logger, sink);

        KE_LOG_INFO(logger, "app", "Hello from C Minimal Log!");
        KE_LOG_DEBUG(logger, "app", "Testing macros with formatting: %d + %d = %d", 2, 2, 4);

        logger->destroy(logger);
    }

    alloc->destroy(alloc);
    printf("--- Demo Complete ---\n");

    return 0;
}

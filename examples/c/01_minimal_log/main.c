#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/logger/console_sink.h>
#include <stdio.h>

int main(void)
{
    printf("--- KernelEngine C Minimal Log Demo ---\n");

    ke_allocator *alloc = ke_allocator_malloc_create();
    if (!alloc) return 1;

    ke_logger *logger = NULL;
    ke_result res = ke_logger_create(alloc, &logger);

    if (res == KE_OK)
    {
        logger->add_sink(logger, ke_console_sink_create(KE_LOG_LEVEL_TRACE));

        ke_log_event ev = {KE_LOG_LEVEL_INFO, "app", "Hello from C Minimal Log!"};
        logger->log(logger, &ev);

        ke_log_event ev2 = {KE_LOG_LEVEL_DEBUG, "app", "Debug message"};
        logger->log(logger, &ev2);

        logger->destroy(logger);
    }

    alloc->destroy(alloc);
    printf("--- Demo Complete ---\n");

    return 0;
}

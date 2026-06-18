#include <kernel_engine/common/error.h>
#include "../common/example_console_sink.h"
#include <stdio.h>

int main(void)
{
    printf("--- KernelEngine C Minimal Log Demo ---\n");

    ke_logger_handle logger_h = {0};
    ke_result res = ke_logger_create(&logger_h, NULL);
    ke_logger *logger = logger_h.ref;

    if (res == KE_OK)
    {
        logger->add_sink(logger, ke_example_console_sink(KE_LOG_LEVEL_TRACE), NULL);

        ke_log_event ev = {KE_LOG_LEVEL_INFO, "app", "Hello from C Minimal Log!"};
        logger->log(logger, &ev);

        ke_log_event ev2 = {KE_LOG_LEVEL_DEBUG, "app", "Debug message"};
        logger->log(logger, &ev2);

        logger_h.destroy(logger_h.ref);
    }
    printf("--- Demo Complete ---\n");

    return 0;
}

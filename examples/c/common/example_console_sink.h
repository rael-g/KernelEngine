#ifndef KERNEL_ENGINE_EXAMPLES_CONSOLE_SINK_H_
#define KERNEL_ENGINE_EXAMPLES_CONSOLE_SINK_H_

// Example-only glue. Console output is a built block (concrete I/O policy)
// and intentionally not provided by the kernel — C# users get
// `ConsoleSink` / `Serilog`; C examples that just want logs on stderr can
// drop this tiny header in.

#include <kernel_engine/logger/logger.h>
#include <stdio.h>

static void ke_example_console_sink_log(ke_logger_sink *self, const ke_log_event *event)
{
    (void)self;
    fprintf(stderr, "[%s] %s: %s\n",
            ke_log_level_to_string(event->level),
            event->tag     ? event->tag     : "",
            event->message ? event->message : "");
    fflush(stderr);
}

static ke_logger_sink ke_example_console_sink(ke_log_level min_level)
{
    ke_logger_sink sink;
    sink.handle    = NULL;
    sink.min_level = (int32_t)min_level;
    sink.log       = ke_example_console_sink_log;
    sink.destroy   = NULL;
    return sink;
}

#endif // KERNEL_ENGINE_EXAMPLES_CONSOLE_SINK_H_

#include <kernel_engine/kernel/logger/console_sink.h>
#include <stdio.h>

static void console_sink_log(ke_logger_sink *self, const ke_log_event *event)
{
    (void)self;
    fprintf(stderr, "[%s] %s: %s\n",
            ke_log_level_to_string(event->level),
            event->tag     ? event->tag     : "",
            event->message ? event->message : "");
    fflush(stderr);
}

ke_logger_sink ke_console_sink_create(ke_log_level min_level)
{
    ke_logger_sink sink;
    sink.handle    = NULL;
    sink.min_level = (int32_t)min_level;
    sink.log       = console_sink_log;
    sink.destroy   = NULL;
    return sink;
}

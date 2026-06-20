#include <kernel_engine/logger/logger.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>

#include <stddef.h>
#include <string.h>

#define KE_LOGGER_MAX_SINKS 8

typedef struct logger_state
{
    ke_logger_sink  sinks[KE_LOGGER_MAX_SINKS];
    int             sink_count;
} logger_state;

static void logger_destroy(ke_logger *self)
{
    if (!self) return;
    logger_state *s = (logger_state *)self->handle;
    for (int i = 0; i < s->sink_count; ++i)
        if (s->sinks[i].destroy) s->sinks[i].destroy(&s->sinks[i]);
    ke_free(s);
    ke_free(self);
}

static void logger_log(ke_logger *self, const ke_log_event *event)
{
    if (!self || !event) return;
    logger_state *s = (logger_state *)self->handle;
    for (int i = 0; i < s->sink_count; ++i)
    {
        ke_logger_sink *sink = &s->sinks[i];
        if (event->level >= sink->min_level && sink->log)
            sink->log(sink, event);
    }
}

static void logger_flush(ke_logger *self)
{
    logger_state *s = (logger_state *)self->handle;
    for (int i = 0; i < s->sink_count; ++i)
        if (s->sinks[i].flush) s->sinks[i].flush(&s->sinks[i]);
}

static bool logger_add_sink(ke_logger *self, ke_logger_sink sink, ke_error **out_error)
{
    if (!self) {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return false;
    }
    logger_state *s = (logger_state *)self->handle;
    if (s->sink_count >= KE_LOGGER_MAX_SINKS) {
        KE_ERROR_SET(out_error, &KE_ERROR_GENERAL, "sink capacity exceeded");
        return false;
    }
    s->sinks[s->sink_count++] = sink;
    return true;
}

const char *ke_log_level_to_string(int32_t level)
{
    switch (level)
    {
    case KE_LOG_LEVEL_TRACE:    return "TRACE";
    case KE_LOG_LEVEL_DEBUG:    return "DEBUG";
    case KE_LOG_LEVEL_INFO:     return "INFO";
    case KE_LOG_LEVEL_WARNING:  return "WARNING";
    case KE_LOG_LEVEL_ERROR:    return "ERROR";
    case KE_LOG_LEVEL_CRITICAL: return "CRITICAL";
    default:                    return "UNKNOWN";
    }
}

ke_logger_handle ke_logger_create(ke_error **out_error)
{
    ke_logger_handle null_handle = {0};

    ke_logger *logger = (ke_logger *)ke_alloc(sizeof(ke_logger), _Alignof(ke_logger));
    if (!logger) {
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "logger allocation failed");
        return null_handle;
    }

    logger_state *state = (logger_state *)ke_alloc(sizeof(logger_state), _Alignof(logger_state));
    if (!state)
    {
        ke_free(logger);
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed");
        return null_handle;
    }

    memset(state, 0, sizeof(*state));

    logger->handle     = state;
    logger->log        = logger_log;
    logger->flush      = logger_flush;
    logger->add_sink   = logger_add_sink;

    ke_logger_handle out_logger;
    out_logger.ref     = logger;
    out_logger.destroy = logger_destroy;
    return out_logger;
}

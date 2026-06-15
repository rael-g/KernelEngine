#include <kernel_engine/logger/logger.h>

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define KE_LOGGER_MAX_SINKS 8

typedef struct logger_state
{
    ke_allocator   *alloc;
    ke_logger_sink  sinks[KE_LOGGER_MAX_SINKS];
    int             sink_count;
} logger_state;

static void logger_destroy(ke_logger *self)
{
    if (!self) return;
    logger_state *s = (logger_state *)self->handle;
    for (int i = 0; i < s->sink_count; ++i)
        if (s->sinks[i].destroy) s->sinks[i].destroy(&s->sinks[i]);
    s->alloc->free(s->alloc, s);
    s->alloc->free(s->alloc, self);
}

static void logger_log(ke_logger *self, const ke_log_event *event)
{
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

static ke_result logger_add_sink(ke_logger *self, ke_logger_sink sink)
{
    logger_state *s = (logger_state *)self->handle;
    if (s->sink_count >= KE_LOGGER_MAX_SINKS) return KE_ERROR;
    s->sinks[s->sink_count++] = sink;
    return KE_OK;
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

ke_result ke_logger_create(ke_allocator *allocator, ke_logger **out_logger)
{
    if (!allocator || !out_logger) return KE_ERROR_INVALID_ARGUMENT;

    ke_logger *logger = (ke_logger *)allocator->alloc(allocator, sizeof(ke_logger), _Alignof(ke_logger));
    if (!logger) return KE_ERROR_OUT_OF_MEMORY;

    logger_state *state = (logger_state *)allocator->alloc(allocator, sizeof(logger_state), _Alignof(logger_state));
    if (!state)
    {
        allocator->free(allocator, logger);
        return KE_ERROR_OUT_OF_MEMORY;
    }

    memset(state, 0, sizeof(*state));
    state->alloc = allocator;

    logger->handle     = state;
    logger->destroy    = logger_destroy;
    logger->log        = logger_log;
    logger->flush      = logger_flush;
    logger->add_sink   = logger_add_sink;

    *out_logger = logger;
    return KE_OK;
}

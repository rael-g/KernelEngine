#include <kernel_engine/logger/logger.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>

#include <stddef.h>
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
    ke_allocator *a = s->alloc;
    a->free(a, s);
    a->free(a, self);
    a->destroy(a);
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

static ke_result logger_add_sink(ke_logger *self, ke_logger_sink sink, ke_error **out_error)
{
    if (!self) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    logger_state *s = (logger_state *)self->handle;
    if (s->sink_count >= KE_LOGGER_MAX_SINKS) return KE_ERROR_SET(out_error, &KE_ERROR_GENERAL, "sink capacity exceeded");
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

ke_result ke_logger_create(ke_logger_handle *out_logger, ke_error **out_error)
{
    if (!out_logger) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");

    ke_allocator *allocator = ke_allocator_malloc_create();
    if (!allocator) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "allocator creation failed");

    ke_logger *logger = (ke_logger *)allocator->alloc(allocator, sizeof(ke_logger), _Alignof(ke_logger));
    if (!logger) { allocator->destroy(allocator); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "logger allocation failed"); }

    logger_state *state = (logger_state *)allocator->alloc(allocator, sizeof(logger_state), _Alignof(logger_state));
    if (!state)
    {
        allocator->free(allocator, logger);
        allocator->destroy(allocator);
        return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed");
    }

    memset(state, 0, sizeof(*state));
    state->alloc = allocator;

    logger->handle     = state;
    logger->log        = logger_log;
    logger->flush      = logger_flush;
    logger->add_sink   = logger_add_sink;

    out_logger->ref     = logger;
    out_logger->destroy = logger_destroy;
    return KE_OK;
}

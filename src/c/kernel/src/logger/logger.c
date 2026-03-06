#include <kernel_engine/kernel/common/array.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <stdlib.h>
#include <string.h>

typedef struct ke_logger_internal
{
    ke_array sinks;
} ke_logger_internal;

static void logger_log(ke_logger *self, const ke_log_event *event)
{
    if (!self || !event) return;
    ke_logger_internal *impl = (ke_logger_internal *)self->handle;

    for (size_t i = 0; i < impl->sinks.size; ++i)
    {
        ke_logger_sink *sink = (ke_logger_sink *)impl->sinks.data[i];
        if (sink && sink->log && event->level >= sink->min_level)
        {
            sink->log(sink, event);
        }
    }
}

static ke_result logger_add_sink(ke_logger *self, ke_logger_sink sink)
{
    if (!self) return KE_ERROR_INVALID_ARGUMENT;
    ke_logger_internal *impl = (ke_logger_internal *)self->handle;

    ke_logger_sink *new_sink = (ke_logger_sink *)self->allocator->alloc(self->allocator, sizeof(ke_logger_sink), 0);
    if (!new_sink) return KE_ERROR_OUT_OF_MEMORY;

    memcpy(new_sink, &sink, sizeof(ke_logger_sink));
    ke_array_push(&impl->sinks, new_sink);

    return KE_OK;
}

static void logger_destroy(ke_logger *self)
{
    if (!self) return;
    ke_logger_internal *impl = (ke_logger_internal *)self->handle;

    for (size_t i = 0; i < impl->sinks.size; ++i)
    {
        ke_logger_sink *sink = (ke_logger_sink *)impl->sinks.data[i];
        if (sink)
        {
            if (sink->destroy) sink->destroy(sink);
            self->allocator->free(self->allocator, sink);
        }
    }

    ke_array_destroy(&impl->sinks);
    self->allocator->free(self->allocator, impl);
    self->allocator->free(self->allocator, self);
}

ke_result ke_logger_create(struct ke_allocator *allocator, ke_logger **out_logger)
{
    if (!out_logger || !allocator) return KE_ERROR_INVALID_ARGUMENT;
    *out_logger = NULL;

    ke_logger_internal *impl = (ke_logger_internal *)allocator->alloc(allocator, sizeof(ke_logger_internal), 0);
    ke_logger *api = (ke_logger *)allocator->alloc(allocator, sizeof(ke_logger), 0);

    if (!impl || !api)
    {
        if (impl) allocator->free(allocator, impl);
        if (api) allocator->free(allocator, api);
        return KE_ERROR_OUT_OF_MEMORY;
    }

    memset(impl, 0, sizeof(ke_logger_internal));
    ke_array_init(&impl->sinks, 4, allocator);

    api->handle = impl;
    api->runtime_limit = 0;
    api->allocator = allocator;

    api->log = logger_log;
    api->add_sink = logger_add_sink;
    api->destroy = logger_destroy;

    *out_logger = api;
    return KE_OK;
}

const char *ke_log_level_to_string(int level)
{
    static const char *levels[] = {"TRACE", "DEBUG", "INFO", "WARN", "ERROR", "CRIT"};
    if (level < 0 || level > 5) return "UNKNOWN";
    return levels[level];
}

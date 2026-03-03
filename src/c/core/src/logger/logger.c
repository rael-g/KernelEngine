#include <kernel_engine/core/common/array.h>
#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/logger/logger.h>
#include <stdlib.h>
#include <string.h>

typedef struct ke_logger_internal
{
    ke_array sinks;
} ke_logger_internal;

static void logger_log(ke_logger *self, int level, const char *tag, const char *message)
{
    if (!self || level < self->runtime_limit)
    {
        return;
    }
    ke_logger_internal *impl = (ke_logger_internal *)self->handle;

    for (size_t i = 0; i < impl->sinks.size; ++i)
    {
        ke_logger_sink *sink = (ke_logger_sink *)impl->sinks.data[i];
        if (sink && sink->log)
        {
            sink->log(sink, level, tag, message);
        }
    }
}

static ke_result logger_add_sink(ke_logger *self, ke_logger_sink sink)
{
    if (!self)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_logger_internal *impl = (ke_logger_internal *)self->handle;
    ke_allocator *alloc = self->allocator;

    ke_logger_sink *sink_ptr = (ke_logger_sink *)alloc->alloc(alloc, sizeof(ke_logger_sink), 0);
    if (!sink_ptr)
    {
        return KE_ERROR_OUT_OF_MEMORY;
    }

    *sink_ptr = sink;
    ke_array_push(&impl->sinks, sink_ptr);
    return KE_OK;
}

static void logger_destroy(ke_logger *self)
{
    if (!self)
    {
        return;
    }
    ke_logger_internal *impl = (ke_logger_internal *)self->handle;
    ke_allocator *alloc = self->allocator;

    for (size_t i = 0; i < impl->sinks.size; ++i)
    {
        ke_logger_sink *sink = (ke_logger_sink *)impl->sinks.data[i];
        if (sink)
        {
            if (sink->destroy)
            {
                sink->destroy(sink);
            }
            alloc->free(alloc, sink);
        }
    }

    ke_array_destroy(&impl->sinks);
    alloc->free(alloc, impl);
    alloc->free(alloc, self);
}

ke_result ke_logger_create(const ke_descriptor *desc, ke_logger **out_logger)
{
    if (!out_logger)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    *out_logger = NULL;

    if (!desc || !desc->allocator)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_allocator *alloc = desc->allocator;

    ke_logger_internal *impl = (ke_logger_internal *)alloc->alloc(alloc, sizeof(ke_logger_internal), 0);
    ke_logger *api = (ke_logger *)alloc->alloc(alloc, sizeof(ke_logger), 0);

    if (!impl || !api)
    {
        if (impl)
        {
            alloc->free(alloc, impl);
        }
        if (api)
        {
            alloc->free(alloc, api);
        }
        return KE_ERROR_OUT_OF_MEMORY;
    }

    memset(impl, 0, sizeof(ke_logger_internal));
    ke_array_init(&impl->sinks, 4, alloc);

    api->handle = impl;
    api->runtime_limit = 0;
    api->allocator = alloc;

    api->log = logger_log;
    api->add_sink = logger_add_sink;
    api->destroy = logger_destroy;

    *out_logger = api;
    return KE_OK;
}

const char *ke_log_level_to_string(int level)
{
    static const char *levels[] = {"TRACE", "DEBUG", "INFO", "WARN", "ERROR", "CRIT"};
    if (level < 0 || level > 5)
    {
        return "UNKNOWN";
    }
    return levels[level];
}

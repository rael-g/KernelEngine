#include <kernel_engine/core/common/array.h>
#include <kernel_engine/core/common/hash.h>
#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/engine/engine.h>
#include <kernel_engine/core/logger/logger.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct ke_engine_internal
{
    ke_array systems;
    ke_logger *logger;
    bool is_running;
} ke_engine_internal;

static ke_result engine_register_system(ke_engine *self, ke_system *sys)
{
    if (!self || !sys)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_engine_internal *eng = (ke_engine_internal *)self->handle;
    KE_LOG_DEBUG(self->logger, "engine", "Registering system with ID: %llu", sys->numeric_id);
    return ke_array_push(&eng->systems, sys);
}

static ke_result engine_initialize(ke_engine *self)
{
    if (!self)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_engine_internal *eng = (ke_engine_internal *)self->handle;
    KE_LOG_INFO(self->logger, "engine", "Initializing engine with %zu systems...", eng->systems.size);
    for (size_t i = 0; i < eng->systems.size; ++i)
    {
        ke_system *sys = (ke_system *)eng->systems.data[i];
        if (sys->on_initialize)
        {
            ke_result res = sys->on_initialize(sys);
            if (res != KE_OK)
            {
                KE_LOG_ERROR(self->logger, "engine", "Failed to initialize system %llu (Result: %d)", sys->numeric_id, res);
                return res;
            }
        }
    }
    eng->is_running = true;
    KE_LOG_INFO(self->logger, "engine", "Engine initialized successfully.");
    return KE_OK;
}

static ke_result engine_shutdown(ke_engine *self)
{
    if (!self)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_engine_internal *eng = (ke_engine_internal *)self->handle;
    if (!eng->is_running)
    {
        return KE_OK;
    }

    KE_LOG_INFO(self->logger, "engine", "Shutting down engine...");
    ke_result final_res = KE_OK;
    for (int i = (int)eng->systems.size - 1; i >= 0; --i)
    {
        ke_system *sys = (ke_system *)eng->systems.data[i];
        if (sys->on_shutdown)
        {
            ke_result res = sys->on_shutdown(sys);
            if (res != KE_OK)
            {
                KE_LOG_ERROR(self->logger, "engine", "Failed to shutdown system %llu (Result: %d)", sys->numeric_id, res);
                final_res = res;
            }
        }
    }
    eng->is_running = false;
    KE_LOG_INFO(self->logger, "engine", "Engine shutdown complete.");
    return final_res;
}

static void engine_destroy(ke_engine *self)
{
    if (!self)
    {
        return;
    }
    engine_shutdown(self);
    ke_engine_internal *eng = (ke_engine_internal *)self->handle;

    // We no longer destroy systems here. 
    // The creator of the system is responsible for its lifecycle.

    ke_array_destroy(&eng->systems);

    ke_allocator *alloc = self->allocator;
    if (alloc)
    {
        alloc->free(alloc, eng);
        alloc->free(alloc, self);
    }
}

static ke_result engine_tick(ke_engine *self, const struct ke_frame *frame)
{
    if (!self)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_engine_internal *eng = (ke_engine_internal *)self->handle;
    for (size_t i = 0; i < eng->systems.size; ++i)
    {
        ke_system *sys = (ke_system *)eng->systems.data[i];
        if (sys->on_update)
        {
            ke_result res = sys->on_update(sys, frame);
            if (res != KE_OK)
            {
                return res;
            }
        }
    }
    return KE_OK;
}

ke_result ke_engine_create(const ke_descriptor *desc, ke_engine **out_engine)
{
    if (!out_engine)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    *out_engine = NULL;

    if (!desc || !desc->allocator)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_allocator *alloc = desc->allocator;

    ke_engine_internal *eng = (ke_engine_internal *)alloc->alloc(alloc, sizeof(ke_engine_internal), 0);
    ke_engine *api = (ke_engine *)alloc->alloc(alloc, sizeof(ke_engine), 0);

    if (!eng || !api)
    {
        if (eng)
        {
            alloc->free(alloc, eng);
        }
        if (api)
        {
            alloc->free(alloc, api);
        }
        return KE_ERROR_OUT_OF_MEMORY;
    }

    memset(eng, 0, sizeof(ke_engine_internal));
    ke_array_init(&eng->systems, 8, alloc);

    api->handle = eng;
    api->allocator = alloc;
    api->logger = desc->logger;

    api->destroy = engine_destroy;
    api->initialize = engine_initialize;
    api->tick = engine_tick;
    api->shutdown = engine_shutdown;
    api->register_system = engine_register_system;

    *out_engine = api;
    return KE_OK;
}

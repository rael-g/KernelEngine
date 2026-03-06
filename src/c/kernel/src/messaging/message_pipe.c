#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

enum
{
    KE_MESSAGE_MAX_COUNT = 1024,
    KE_MESSAGE_DATA_POOL_SIZE = (128 * 1024)
};

typedef struct ke_message_meta
{
    uint64_t msg_id;
    size_t size;
    size_t data_offset;
} ke_message_meta;

typedef struct ke_message_pipe_impl
{
    ke_message_meta metadata[KE_MESSAGE_MAX_COUNT];
    uint8_t data_pool[KE_MESSAGE_DATA_POOL_SIZE];
    size_t message_count;
    size_t pool_offset;
    size_t reader_offsets[32];
} ke_message_pipe_impl;

static ke_result pipe_broadcast(ke_message_pipe *self, uint64_t msg_id, const void *data, size_t size)
{
    if (!self) return KE_ERROR_INVALID_ARGUMENT;
    ke_message_pipe_impl *impl = (ke_message_pipe_impl *)self->handle;
    if (impl->message_count >= KE_MESSAGE_MAX_COUNT || impl->pool_offset + size > KE_MESSAGE_DATA_POOL_SIZE)
    {
        return KE_ERROR;
    }
    ke_message_meta *meta = &impl->metadata[impl->message_count];
    meta->msg_id = msg_id;
    meta->size = size;
    meta->data_offset = impl->pool_offset;
    if (data && size > 0)
    {
        memcpy(&impl->data_pool[impl->pool_offset], data, size);
    }
    impl->pool_offset += size;
    impl->message_count++;
    return KE_OK;
}

static ke_result pipe_create_reader(ke_message_pipe *self, ke_message_pipe **out_reader)
{
    if (!self || !out_reader) return KE_ERROR_INVALID_ARGUMENT;
    *out_reader = self;
    return KE_OK;
}

static bool pipe_try_receive(ke_message_pipe *self, uint64_t msg_id, void *out_data, size_t max_size)
{
    if (!self) return false;
    ke_message_pipe_impl *impl = (ke_message_pipe_impl *)self->handle;
    size_t *offset_ptr = &impl->reader_offsets[0];
    while (*offset_ptr < impl->message_count)
    {
        ke_message_meta *meta = &impl->metadata[*offset_ptr];
        (*offset_ptr)++;
        if (meta->msg_id == msg_id || msg_id == 0)
        {
            if (out_data && max_size >= meta->size)
            {
                memcpy(out_data, &impl->data_pool[meta->data_offset], meta->size);
            }
            return true;
        }
    }
    return false;
}

static ke_result pipe_pump(ke_message_pipe *self)
{
    if (!self) return KE_ERROR_INVALID_ARGUMENT;
    ke_message_pipe_impl *impl = (ke_message_pipe_impl *)self->handle;
    impl->message_count = 0;
    impl->pool_offset = 0;
    memset(impl->reader_offsets, 0, sizeof(impl->reader_offsets));
    return KE_OK;
}

static void pipe_destroy(ke_message_pipe *self)
{
    if (!self) return;
    ke_allocator *alloc = self->allocator;
    if (alloc)
    {
        alloc->free(alloc, self->handle);
        alloc->free(alloc, self);
    }
}

ke_result ke_message_pipe_create(struct ke_allocator *allocator, struct ke_logger *logger, ke_message_pipe **out_pipe)
{
    if (!out_pipe || !allocator) return KE_ERROR_INVALID_ARGUMENT;
    *out_pipe = NULL;

    ke_message_pipe_impl *impl = (ke_message_pipe_impl *)allocator->alloc(allocator, sizeof(ke_message_pipe_impl), 0);
    ke_message_pipe *api = (ke_message_pipe *)allocator->alloc(allocator, sizeof(ke_message_pipe), 0);

    if (!impl || !api)
    {
        if (impl) allocator->free(allocator, impl);
        if (api) allocator->free(allocator, api);
        return KE_ERROR_OUT_OF_MEMORY;
    }

    memset(impl, 0, sizeof(ke_message_pipe_impl));

    api->handle = impl;
    api->allocator = allocator;
    api->logger = logger;

    api->broadcast = pipe_broadcast;
    api->create_reader = pipe_create_reader;
    api->try_receive = pipe_try_receive;
    api->pump = pipe_pump;
    api->destroy = pipe_destroy;

    *out_pipe = api;
    return KE_OK;
}

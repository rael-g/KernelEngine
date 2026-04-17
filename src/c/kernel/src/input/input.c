#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/input/input.h>
#include <kernel_engine/kernel/input/input_messages.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <stdlib.h>
#include <string.h>

enum { MAX_KEYS = 512 };

typedef struct ke_input_internal
{
    bool keys_down[MAX_KEYS];
    bool keys_pressed[MAX_KEYS];
    bool keys_released[MAX_KEYS];
} ke_input_internal;

static ke_result input_update(ke_input *self)
{
    if (!self) return KE_ERROR_INVALID_ARGUMENT;
    ke_input_internal *impl = (ke_input_internal *)self->handle;
    ke_message_pipe *pipe = self->message_pipe;

    memset(impl->keys_pressed, 0, sizeof(impl->keys_pressed));
    memset(impl->keys_released, 0, sizeof(impl->keys_released));

    if (!pipe) return KE_OK;

    ke_msg_key_event msg;
    while (pipe->try_receive(pipe, KE_MSG_KEY_EVENT, &msg, sizeof(msg)))
    {
        if (msg.key < 0 || msg.key >= MAX_KEYS) continue;

        if (msg.action == 1)
        {
            if (!impl->keys_down[msg.key]) impl->keys_pressed[msg.key] = true;
            impl->keys_down[msg.key] = true;
        }
        else if (msg.action == 0)
        {
            impl->keys_released[msg.key] = true;
            impl->keys_down[msg.key] = false;
        }
    }
    return KE_OK;
}

static ke_bool input_is_key_pressed(ke_input *self, int32_t key)
{
    if (!self || key < 0 || key >= MAX_KEYS) return false;
    return ((ke_input_internal *)self->handle)->keys_pressed[key];
}

static ke_bool input_is_key_released(ke_input *self, int32_t key)
{
    if (!self || key < 0 || key >= MAX_KEYS) return false;
    return ((ke_input_internal *)self->handle)->keys_released[key];
}

static ke_bool input_is_key_down(ke_input *self, int32_t key)
{
    if (!self || key < 0 || key >= MAX_KEYS) return false;
    return ((ke_input_internal *)self->handle)->keys_down[key];
}

static void input_destroy(ke_input *self)
{
    if (!self) return;
    if (self->allocator)
    {
        self->allocator->free(self->allocator, self->handle);
        self->allocator->free(self->allocator, self);
    }
}

ke_result ke_input_create(struct ke_allocator *allocator, struct ke_logger *logger, struct ke_message_pipe *pipe, ke_input **out_input)
{
    if (!out_input || !allocator) return KE_ERROR_INVALID_ARGUMENT;
    *out_input = NULL;

    ke_input_internal *impl = (ke_input_internal *)allocator->alloc(allocator, sizeof(ke_input_internal), 0);
    ke_input *api = (ke_input *)allocator->alloc(allocator, sizeof(ke_input), 0);

    if (!impl || !api)
    {
        if (impl) allocator->free(allocator, impl);
        if (api) allocator->free(allocator, api);
        return KE_ERROR_OUT_OF_MEMORY;
    }
    memset(impl, 0, sizeof(ke_input_internal));

    api->handle = impl;
    api->allocator = allocator;
    api->logger = logger;
    api->message_pipe = pipe;

    api->destroy = input_destroy;
    api->update = input_update;
    api->is_key_pressed = input_is_key_pressed;
    api->is_key_released = input_is_key_released;
    api->is_key_down = input_is_key_down;

    *out_input = api;
    return KE_OK;
}

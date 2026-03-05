#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/input/input.h>
#include <kernel_engine/kernel/input/input_messages.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <stdlib.h>
#include <string.h>

enum
{
    MAX_KEYS = 512
};

typedef struct ke_input_internal
{
    bool keys_down[MAX_KEYS];
    bool keys_pressed[MAX_KEYS];
    bool keys_released[MAX_KEYS];
} ke_input_internal;

static ke_result input_update(ke_input *self)
{
    if (!self)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_input_internal *impl = (ke_input_internal *)self->handle;
    ke_message_pipe *pipe = self->message_pipe;

    // Reset frame-specific states
    memset(impl->keys_pressed, 0, sizeof(impl->keys_pressed));
    memset(impl->keys_released, 0, sizeof(impl->keys_released));

    if (!pipe)
    {
        return KE_OK;
    }

    ke_msg_key_event msg;
    while (pipe->try_receive(pipe, KE_MSG_KEY_EVENT, &msg, sizeof(msg)))
    {
        if (msg.key < 0 || msg.key >= MAX_KEYS)
        {
            continue;
        }

        if (msg.action == 1)
        { // Pressed
            if (!impl->keys_down[msg.key])
            {
                impl->keys_pressed[msg.key] = true;
            }
            impl->keys_down[msg.key] = true;
        }
        else if (msg.action == 0)
        { // Released
            impl->keys_released[msg.key] = true;
            impl->keys_down[msg.key] = false;
        }
    }
    return KE_OK;
}

static bool input_is_key_pressed(ke_input *self, int key)
{
    if (!self || key < 0 || key >= MAX_KEYS)
    {
        return false;
    }
    return ((ke_input_internal *)self->handle)->keys_pressed[key];
}

static bool input_is_key_released(ke_input *self, int key)
{
    if (!self || key < 0 || key >= MAX_KEYS)
    {
        return false;
    }
    return ((ke_input_internal *)self->handle)->keys_released[key];
}

static bool input_is_key_down(ke_input *self, int key)
{
    if (!self || key < 0 || key >= MAX_KEYS)
    {
        return false;
    }
    return ((ke_input_internal *)self->handle)->keys_down[key];
}

static void input_destroy(ke_input *self)
{
    if (!self)
    {
        return;
    }
    if (self->allocator)
    {
        self->allocator->free(self->allocator, self->handle);
        self->allocator->free(self->allocator, self);
    }
}

ke_result ke_input_create(const ke_descriptor *desc, ke_input **out_input)
{
    if (!out_input)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    *out_input = NULL;

    if (!desc || !desc->allocator)
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_allocator *alloc = desc->allocator;

    ke_input_internal *impl = (ke_input_internal *)alloc->alloc(alloc, sizeof(ke_input_internal), 0);
    ke_input *api = (ke_input *)alloc->alloc(alloc, sizeof(ke_input), 0);

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
    memset(impl, 0, sizeof(ke_input_internal));

    api->handle = impl;
    api->allocator = alloc;
    api->logger = desc->logger;
    api->message_pipe = desc->message_pipe;

    api->destroy = input_destroy;
    api->update = input_update;
    api->is_key_pressed = input_is_key_pressed;
    api->is_key_released = input_is_key_released;
    api->is_key_down = input_is_key_down;

    *out_input = api;
    return KE_OK;
}

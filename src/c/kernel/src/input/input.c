#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/input/input.h>
#include <stdlib.h>
#include <string.h>

#define MAX_KEYS 512

typedef struct ke_input_internal
{
    bool keys_down[MAX_KEYS];
    bool keys_pressed[MAX_KEYS];
    bool keys_released[MAX_KEYS];

    float mouse_x, mouse_y;
    float mouse_dx, mouse_dy;
    float scroll_dx, scroll_dy;
    uint32_t mouse_buttons_down;
    uint32_t mouse_buttons_pressed;
    uint32_t mouse_buttons_released;
} ke_input_internal;

static ke_result input_update(ke_input *self)
{
    if (!self) return KE_ERROR_INVALID_ARGUMENT;
    ke_input_internal *impl = (ke_input_internal *)self->handle;

    memset(impl->keys_pressed, 0, sizeof(impl->keys_pressed));
    memset(impl->keys_released, 0, sizeof(impl->keys_released));

    impl->mouse_dx = 0;
    impl->mouse_dy = 0;
    impl->scroll_dx = 0;
    impl->scroll_dy = 0;
    impl->mouse_buttons_pressed = 0;
    impl->mouse_buttons_released = 0;

    return KE_OK;
}

static void input_on_key(ke_input *self, int32_t key, int32_t action)
{
    if (!self || key < 0 || key >= MAX_KEYS) return;
    ke_input_internal *impl = (ke_input_internal *)self->handle;

    if (action == 1) {
        if (!impl->keys_down[key]) impl->keys_pressed[key] = true;
        impl->keys_down[key] = true;
    } else if (action == 0) {
        impl->keys_released[key] = true;
        impl->keys_down[key] = false;
    }
}

static void input_on_mouse_move(ke_input *self, float x, float y)
{
    if (!self) return;
    ke_input_internal *impl = (ke_input_internal *)self->handle;
    impl->mouse_dx += (x - impl->mouse_x);
    impl->mouse_dy += (y - impl->mouse_y);
    impl->mouse_x = x;
    impl->mouse_y = y;
}

static void input_on_mouse_button(ke_input *self, int32_t button, int32_t action)
{
    if (!self || button < 0 || button >= 32) return;
    ke_input_internal *impl = (ke_input_internal *)self->handle;
    uint32_t mask = (1u << button);
    if (action == 1) {
        if (!(impl->mouse_buttons_down & mask)) impl->mouse_buttons_pressed |= mask;
        impl->mouse_buttons_down |= mask;
    } else if (action == 0) {
        impl->mouse_buttons_released |= mask;
        impl->mouse_buttons_down &= ~mask;
    }
}

static void input_on_mouse_scroll(ke_input *self, float dx, float dy)
{
    if (!self) return;
    ke_input_internal *impl = (ke_input_internal *)self->handle;
    impl->scroll_dx += dx;
    impl->scroll_dy += dy;
}

static ke_bool input_is_key_pressed(ke_input *self, int32_t key)
{
    if (!self || key < 0 || key >= MAX_KEYS) return 0;
    ke_input_internal *impl = (ke_input_internal *)self->handle;
    return impl->keys_pressed[key] ? 1 : 0;
}

static ke_bool input_is_key_released(ke_input *self, int32_t key)
{
    if (!self || key < 0 || key >= MAX_KEYS) return 0;
    ke_input_internal *impl = (ke_input_internal *)self->handle;
    return impl->keys_released[key] ? 1 : 0;
}

static ke_bool input_is_key_down(ke_input *self, int32_t key)
{
    if (!self || key < 0 || key >= MAX_KEYS) return 0;
    ke_input_internal *impl = (ke_input_internal *)self->handle;
    return impl->keys_down[key] ? 1 : 0;
}

static void input_get_snapshot(ke_input *self, ke_input_snapshot *out)
{
    if (!self || !out) return;
    ke_input_internal *impl = (ke_input_internal *)self->handle;

    memset(out, 0, sizeof(ke_input_snapshot));

    for (int i = 0; i < MAX_KEYS; ++i)
    {
        int word = i / 64;
        uint64_t bit = (1ULL << (i % 64));
        if (impl->keys_down[i])     out->keys_down[word]     |= bit;
        if (impl->keys_pressed[i])  out->keys_pressed[word]  |= bit;
        if (impl->keys_released[i]) out->keys_released[word] |= bit;
    }

    out->mouse_x = impl->mouse_x;
    out->mouse_y = impl->mouse_y;
    out->mouse_dx = impl->mouse_dx;
    out->mouse_dy = impl->mouse_dy;
    out->scroll_dx = impl->scroll_dx;
    out->scroll_dy = impl->scroll_dy;

    out->mouse_buttons_down     = impl->mouse_buttons_down;
    out->mouse_buttons_pressed  = impl->mouse_buttons_pressed;
    out->mouse_buttons_released = impl->mouse_buttons_released;
}

static void input_destroy(ke_input *self)
{
    if (!self) return;
    ke_allocator *a = self->allocator;
    a->free(a, self->handle);
    a->free(a, self);
}

ke_result ke_input_create(ke_allocator *alloc, struct ke_logger *log, ke_input **out_input)
{
    if (!alloc || !out_input) return KE_ERROR_INVALID_ARGUMENT;

    ke_input *api = (ke_input *)alloc->alloc(alloc, sizeof(ke_input), 8);
    if (!api) return KE_ERROR_OUT_OF_MEMORY;
    ke_input_internal *impl = (ke_input_internal *)alloc->alloc(alloc, sizeof(ke_input_internal), 8);
    if (!impl) { alloc->free(alloc, api); return KE_ERROR_OUT_OF_MEMORY; }
    memset(impl, 0, sizeof(ke_input_internal));

    api->handle = impl;
    api->allocator = alloc;
    api->logger = log;
    api->destroy = input_destroy;
    api->update = input_update;
    
    api->is_key_pressed = input_is_key_pressed;
    api->is_key_down = input_is_key_down;
    api->is_key_released = input_is_key_released;
    api->get_snapshot = input_get_snapshot;

    api->on_key = input_on_key;
    api->on_mouse_move = input_on_mouse_move;
    api->on_mouse_button = input_on_mouse_button;
    api->on_mouse_scroll = input_on_mouse_scroll;

    *out_input = api;
    return KE_OK;
}

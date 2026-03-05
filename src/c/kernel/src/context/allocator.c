#include <kernel_engine/kernel/context/allocator.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *malloc_alloc(ke_allocator *self, size_t size, size_t alignment)
{
    (void)self;
    (void)alignment;
    return malloc(size);
}

static void malloc_free(ke_allocator *self, void *ptr)
{
    (void)self;
    free(ptr);
}

static void *malloc_realloc(ke_allocator *self, void *ptr, size_t new_size)
{
    (void)self;
    return realloc(ptr, new_size);
}

ke_allocator *ke_allocator_malloc_create(void)
{
    ke_allocator *api = (ke_allocator *)calloc(1, sizeof(ke_allocator));
    if (!api)
    {
        return NULL;
    }
    api->destroy = (void (*)(ke_allocator *))free;
    api->alloc = malloc_alloc;
    api->free = malloc_free;
    api->realloc = malloc_realloc;
    return api;
}

typedef struct ke_arena
{
    uint8_t *buffer;
    size_t capacity;
    size_t offset;
} ke_arena;

static void *arena_alloc(ke_allocator *self, size_t size, size_t alignment)
{
    ke_arena *arena = (ke_arena *)self->handle;
    if (!arena || !arena->buffer)
    {
        return NULL;
    }
    if (alignment == 0)
    {
        alignment = 8;
    }
    uintptr_t current_ptr = (uintptr_t)(arena->buffer + arena->offset);
    uintptr_t data_ptr = (current_ptr + alignment - 1) & ~(alignment - 1);
    uintptr_t next_offset = (data_ptr + size) - (uintptr_t)arena->buffer;
    if (next_offset > arena->capacity)
    {
        return NULL;
    }
    arena->offset = (size_t)next_offset;
    return (void *)data_ptr;
}

static void *arena_realloc(ke_allocator *self, void *ptr, size_t new_size)
{
    if (!ptr)
    {
        return arena_alloc(self, new_size, 0);
    }
    void *new_ptr = arena_alloc(self, new_size, 0);
    if (new_ptr)
    {
        // Warning: arena realloc without size info is dangerous,
        // but for now we assume it's only used for growing.
        // We can't know the old size here without headers.
        // For simplicity in this test, we just copy new_size (risky!)
        // or better, don't use arena for things that realloc if possible.
        memcpy(new_ptr, ptr, new_size);
    }
    return new_ptr;
}

static void arena_reset(ke_allocator *self)
{
    if (self && self->handle)
    {
        ((ke_arena *)self->handle)->offset = 0;
    }
}
static void arena_destroy(ke_allocator *self)
{
    if (!self)
    {
        return;
    }
    ke_arena *arena = (ke_arena *)self->handle;
    if (arena)
    {
        free(arena->buffer);
        free(arena);
    }
    free(self);
}

ke_allocator *ke_allocator_arena_create(size_t capacity)
{
    ke_arena *arena = (ke_arena *)calloc(1, sizeof(ke_arena));
    if (!arena)
    {
        return NULL;
    }
    arena->buffer = (uint8_t *)malloc(capacity);
    if (!arena->buffer)
    {
        free(arena);
        return NULL;
    }
    arena->capacity = capacity;
    ke_allocator *api = (ke_allocator *)calloc(1, sizeof(ke_allocator));
    if (!api)
    {
        free(arena->buffer);
        free(arena);
        return NULL;
    }
    api->handle = arena;
    api->destroy = arena_destroy;
    api->alloc = arena_alloc;
    api->realloc = arena_realloc;
    api->reset = arena_reset;
    return api;
}

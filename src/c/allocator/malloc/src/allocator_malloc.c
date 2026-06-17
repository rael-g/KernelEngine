#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/common/error.h>
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
    if (!self || size == 0)
    {
        return NULL;
    }
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

// --- Proxy Allocator (Memory Tracking) ---

#include <kernel_engine/logger/logger.h>

typedef struct proxy_impl
{
    ke_allocator *inner;
    char name[64];
    ke_allocator_stats stats;
} proxy_impl;

// Note: Using a simple header to track size for free/realloc stats.
// In a production engine we'd use a more robust way or ask the inner allocator.
typedef struct alloc_header
{
    size_t size;
} alloc_header;

static void *proxy_alloc(ke_allocator *self, size_t size, size_t alignment)
{
    if (!self || !self->handle) return NULL;
    proxy_impl *impl = (proxy_impl *)self->handle;
    if (!impl->inner) return NULL;
    
    size_t total_size = size + sizeof(alloc_header);
    
    uint8_t *ptr = (uint8_t *)impl->inner->alloc(impl->inner, total_size, alignment);
    if (!ptr) return NULL;

    alloc_header *header = (alloc_header *)ptr;
    header->size = size;

    impl->stats.total_allocated += size;
    impl->stats.active_bytes += size;
    impl->stats.active_allocs++;

    return ptr + sizeof(alloc_header);
}

static void proxy_free(ke_allocator *self, void *ptr)
{
    if (!ptr) return;
    proxy_impl *impl = (proxy_impl *)self->handle;
    
    uint8_t *base_ptr = (uint8_t *)ptr - sizeof(alloc_header);
    alloc_header *header = (alloc_header *)base_ptr;
    
    size_t size = header->size;
    impl->stats.total_freed += size;
    impl->stats.active_bytes -= size;
    impl->stats.active_allocs--;

    impl->inner->free(impl->inner, base_ptr);
}

static void *proxy_realloc(ke_allocator *self, void *ptr, size_t new_size)
{
    if (!ptr) return proxy_alloc(self, new_size, 0);
    
    proxy_impl *impl = (proxy_impl *)self->handle;
    uint8_t *base_ptr = (uint8_t *)ptr - sizeof(alloc_header);
    alloc_header *header = (alloc_header *)base_ptr;
    
    size_t old_size = header->size;
    size_t total_new_size = new_size + sizeof(alloc_header);
    
    uint8_t *new_base = (uint8_t *)impl->inner->realloc(impl->inner, base_ptr, total_new_size);
    if (!new_base) return NULL;

    header = (alloc_header *)new_base;
    header->size = new_size;

    impl->stats.total_allocated += new_size;
    impl->stats.total_freed += old_size;
    impl->stats.active_bytes = (impl->stats.active_bytes - old_size) + new_size;

    return new_base + sizeof(alloc_header);
}

static void proxy_destroy(ke_allocator *self)
{
    if (!self) return;
    proxy_impl *impl = (proxy_impl *)self->handle;
    free(impl);
    free(self);
}

ke_allocator *ke_allocator_proxy_create(ke_allocator *inner, const char *name)
{
    if (!inner) return NULL;

    proxy_impl *impl = (proxy_impl *)calloc(1, sizeof(proxy_impl));
    if (!impl) return NULL;

    impl->inner = inner;
    if (name) strncpy(impl->name, name, sizeof(impl->name) - 1);
    else strcpy(impl->name, "unnamed_proxy");

    ke_allocator *api = (ke_allocator *)calloc(1, sizeof(ke_allocator));
    if (!api) {
        free(impl);
        return NULL;
    }

    api->handle = impl;
    api->destroy = proxy_destroy;
    api->alloc = proxy_alloc;
    api->free = proxy_free;
    api->realloc = proxy_realloc;

    return api;
}

ke_result ke_allocator_proxy_get_stats(ke_allocator *proxy, ke_allocator_stats *out_stats, ke_error **out_error)
{
    if (!proxy || !out_stats) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    // Simple check: we don't have a tag system yet, so we assume the handle matches our struct layout.
    // In a safer impl we'd have a magic number.
    proxy_impl *impl = (proxy_impl *)proxy->handle;
    *out_stats = impl->stats;
    return KE_OK;
}

void ke_allocator_proxy_report(ke_allocator *proxy, struct ke_logger *logger)
{
    if (!proxy) return;
    proxy_impl *impl = (proxy_impl *)proxy->handle;
    ke_allocator_stats *s = &impl->stats;

    char buf[256];
    snprintf(buf, sizeof(buf), "Allocator Proxy '%s' Report:", impl->name);
    
    if (logger) {
        ke_log_event ev = { KE_LOG_LEVEL_INFO, "memory", buf };
        logger->log(logger, &ev);
        
        snprintf(buf, sizeof(buf), "  Active: %u allocs, %zu bytes", s->active_allocs, s->active_bytes);
        logger->log(logger, &ev);

        snprintf(buf, sizeof(buf), "  Total: %zu allocated, %zu freed", s->total_allocated, s->total_freed);
        logger->log(logger, &ev);

        if (s->active_allocs > 0) {
            snprintf(buf, sizeof(buf), "  WARNING: %u LEAKS DETECTED!", s->active_allocs);
            ev.level = KE_LOG_LEVEL_WARNING;
            logger->log(logger, &ev);
        }
    } else {
        fprintf(stderr, "%s\n", buf);
        fprintf(stderr, "  Active: %u allocs, %zu bytes\n", s->active_allocs, s->active_bytes);
        fprintf(stderr, "  Total: %zu allocated, %zu freed\n", s->total_allocated, s->total_freed);
        if (s->active_allocs > 0) {
            fprintf(stderr, "  WARNING: %u LEAKS DETECTED!\n", s->active_allocs);
        }
    }
}

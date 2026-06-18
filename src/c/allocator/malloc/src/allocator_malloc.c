#include <kernel_engine/allocator/allocator.h>
#include <stdlib.h>
#include <string.h>

/*
 * Header layout stored just before the aligned pointer returned to callers:
 *
 *   [raw malloc]  (padding)  [size_t: alloc_size]  [uint16_t: offset]  [returned ptr]
 *                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
 *                            KE_HEADER_BYTES = sizeof(size_t) + sizeof(uint16_t)
 *
 * 'offset' = (uintptr_t)returned_ptr - (uintptr_t)raw_malloc.
 * Stored as uint16_t so alignments up to 65535 are supported.
 */

#define KE_HEADER_BYTES (sizeof(size_t) + sizeof(uint16_t))

static void  header_write(void *aligned, size_t alloc_size, uint16_t offset);
static size_t header_read_size(const void *aligned);
static void *header_raw(const void *aligned);

static void header_write(void *aligned, size_t alloc_size, uint16_t offset)
{
    memcpy((uint8_t *)aligned - sizeof(uint16_t),              &offset,     sizeof(uint16_t));
    memcpy((uint8_t *)aligned - sizeof(uint16_t) - sizeof(size_t), &alloc_size, sizeof(size_t));
}

static size_t header_read_size(const void *aligned)
{
    size_t s;
    memcpy(&s, (const uint8_t *)aligned - sizeof(uint16_t) - sizeof(size_t), sizeof(size_t));
    return s;
}

static void *header_raw(const void *aligned)
{
    uint16_t offset;
    memcpy(&offset, (const uint8_t *)aligned - sizeof(uint16_t), sizeof(uint16_t));
    return (void *)((const uint8_t *)aligned - offset);
}

/* ── Heap allocation ──────────────────────────────────────────────────────── */

void *ke_alloc(size_t size, size_t alignment)
{
    if (size == 0)
        return NULL;
    if (alignment < 1)
        alignment = 1;

    /* total must fit: header bytes + alignment padding + payload. */
    size_t total = size + alignment + KE_HEADER_BYTES;
    void  *raw   = malloc(total);
    if (!raw)
        return NULL;

    /* First address that leaves room for the header before it. */
    uintptr_t base    = (uintptr_t)raw + KE_HEADER_BYTES;
    uintptr_t aligned = (base + alignment - 1) & ~(uintptr_t)(alignment - 1);
    uint16_t  offset  = (uint16_t)(aligned - (uintptr_t)raw);

    header_write((void *)aligned, size, offset);
    return (void *)aligned;
}

void ke_free(void *ptr)
{
    if (!ptr)
        return;
    free(header_raw(ptr));
}

void *ke_realloc(void *ptr, size_t new_size)
{
    if (!ptr)
        return ke_alloc(new_size, 1);
    if (new_size == 0)
    {
        ke_free(ptr);
        return NULL;
    }
    size_t old_size = header_read_size(ptr);
    void  *new_ptr  = ke_alloc(new_size, 1);
    if (!new_ptr)
        return NULL;
    size_t copy = old_size < new_size ? old_size : new_size;
    memcpy(new_ptr, ptr, copy);
    ke_free(ptr);
    return new_ptr;
}

/* ── Arena ────────────────────────────────────────────────────────────────── */

void ke_arena_init(ke_arena *arena, size_t capacity)
{
    if (!arena)
        return;
    arena->buffer   = (uint8_t *)malloc(capacity);
    arena->capacity = arena->buffer ? capacity : 0;
    arena->offset   = 0;
}

void *ke_arena_alloc(ke_arena *arena, size_t size, size_t alignment)
{
    if (!arena || !arena->buffer || size == 0)
        return NULL;
    if (alignment == 0)
        alignment = 8;
    uintptr_t cur     = (uintptr_t)(arena->buffer + arena->offset);
    uintptr_t aligned = (cur + alignment - 1) & ~(uintptr_t)(alignment - 1);
    size_t    next    = (size_t)(aligned + size - (uintptr_t)arena->buffer);
    if (next > arena->capacity)
        return NULL;
    arena->offset = next;
    return (void *)aligned;
}

void ke_arena_reset(ke_arena *arena)
{
    if (arena)
        arena->offset = 0;
}

void ke_arena_destroy(ke_arena *arena)
{
    if (!arena)
        return;
    free(arena->buffer);
    arena->buffer   = NULL;
    arena->capacity = 0;
    arena->offset   = 0;
}

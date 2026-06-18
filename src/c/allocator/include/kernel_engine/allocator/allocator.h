#ifndef KERNEL_ENGINE_ALLOCATOR_ALLOCATOR_H_
#define KERNEL_ENGINE_ALLOCATOR_ALLOCATOR_H_

/*
 * Internal memory utilities — NOT engine API.
 *
 * ke_alloc / ke_free / ke_realloc: plain malloc-backed functions with
 * alignment support. Linked PRIVATE by each impl; never passed as parameters.
 *
 * ke_arena: bump allocator for short-lived scratch memory. Concrete struct,
 * not a vtable — callers own the struct directly.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /* ── Heap allocation ──────────────────────────────────────────────────── */

    void *ke_alloc(size_t size, size_t alignment);
    void  ke_free(void *ptr);
    void *ke_realloc(void *ptr, size_t new_size);

    /* ── Arena (bump allocator) ───────────────────────────────────────────── */

    typedef struct ke_arena
    {
        uint8_t *buffer;
        size_t   capacity;
        size_t   offset;
    } ke_arena;

    void  ke_arena_init(ke_arena *arena, size_t capacity);
    void *ke_arena_alloc(ke_arena *arena, size_t size, size_t alignment);
    void  ke_arena_reset(ke_arena *arena);
    void  ke_arena_destroy(ke_arena *arena);

#ifdef __cplusplus
}
#endif

#endif /* KERNEL_ENGINE_ALLOCATOR_ALLOCATOR_H_ */

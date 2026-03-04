#ifndef KERNEL_ENGINE_CORE_CONTEXT_ALLOCATOR_H_
#define KERNEL_ENGINE_CORE_CONTEXT_ALLOCATOR_H_

#include <kernel_engine/core/context/types.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_ALLOCATOR_DEFAULT "ke_alloc_default"
#define KE_ID_ALLOCATOR_SCRATCH "ke_alloc_scratch"

    /// @brief Abstraction for memory allocation.
    typedef struct ke_allocator
    {
        void *handle;
        void (*destroy)(struct ke_allocator *self);

        void *(*alloc)(struct ke_allocator *self, size_t size, size_t alignment);
        void (*free)(struct ke_allocator *self, void *ptr);
        void *(*realloc)(struct ke_allocator *self, void *ptr, size_t new_size);
        void (*reset)(struct ke_allocator *self);
    } ke_allocator;

    /// @brief Creates an allocator based on standard malloc.
    KE_API ke_allocator *ke_allocator_malloc_create(void);

    /// @brief Creates an arena allocator with fixed capacity.
    KE_API ke_allocator *ke_allocator_arena_create(size_t fixed_capacity);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_CORE_CONTEXT_ALLOCATOR_H_

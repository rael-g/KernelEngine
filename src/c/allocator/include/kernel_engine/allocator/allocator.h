#ifndef KERNEL_ENGINE_ALLOCATOR_ALLOCATOR_H_
#define KERNEL_ENGINE_ALLOCATOR_ALLOCATOR_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/common/error.h>
#include <stddef.h>
#include <stdint.h>

#ifdef KE_ALLOCATOR_STATIC
#  define KE_ALLOCATOR_API
#elif defined(KE_ALLOCATOR_EXPORT)
#  define KE_ALLOCATOR_API KE_EXPORT
#else
#  define KE_ALLOCATOR_API KE_IMPORT
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    struct ke_logger;

#define KE_ID_ALLOCATOR_DEFAULT "ke_alloc_default"
#define KE_ID_ALLOCATOR_SCRATCH "ke_alloc_scratch"

    /// @brief Abstraction for memory allocation.
    typedef struct ke_allocator
    {
        void *handle;
        void (*destroy)(struct ke_allocator *self);

        void *(*alloc)(struct ke_allocator *self, size_t size, size_t alignment);
        void  (*free)(struct ke_allocator *self, void *ptr);
        void *(*realloc)(struct ke_allocator *self, void *ptr, size_t new_size);
        void  (*reset)(struct ke_allocator *self);
    } ke_allocator;

    /// @brief Creates an allocator backed by standard malloc.
    KE_ALLOCATOR_API ke_allocator *ke_allocator_malloc_create(void);

    /// @brief Creates an arena allocator with fixed capacity.
    KE_ALLOCATOR_API ke_allocator *ke_allocator_arena_create(size_t fixed_capacity);

    /// @brief Statistics for an allocator.
    typedef struct ke_allocator_stats
    {
        size_t   total_allocated;
        size_t   total_freed;
        size_t   active_bytes;
        uint32_t active_allocs;
    } ke_allocator_stats;

    /// @brief Creates a proxy allocator that tracks statistics of another allocator.
    KE_ALLOCATOR_API ke_allocator *ke_allocator_proxy_create(ke_allocator *inner, const char *name);

    /// @brief Retrieves current statistics from a proxy allocator.
    KE_ALLOCATOR_API ke_result ke_allocator_proxy_get_stats(ke_allocator *proxy,
                                                             ke_allocator_stats *out_stats);

    /// @brief Logs a summary of the proxy allocator and reports leaks if any.
    KE_ALLOCATOR_API void ke_allocator_proxy_report(ke_allocator *proxy, struct ke_logger *logger);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_ALLOCATOR_ALLOCATOR_H_

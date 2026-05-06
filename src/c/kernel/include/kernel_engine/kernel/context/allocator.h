#ifndef KERNEL_ENGINE_KERNEL_CONTEXT_ALLOCATOR_H_
#define KERNEL_ENGINE_KERNEL_CONTEXT_ALLOCATOR_H_

#include <kernel_engine/kernel/context/types.h>
#include <stddef.h>

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
        void (*free)(struct ke_allocator *self, void *ptr);
        void *(*realloc)(struct ke_allocator *self, void *ptr, size_t new_size);
        void (*reset)(struct ke_allocator *self);
    } ke_allocator;

    /// @brief Creates an allocator based on standard malloc.
    KE_API ke_allocator *ke_allocator_malloc_create(void);

    /// @brief Creates an arena allocator with fixed capacity.
    KE_API ke_allocator *ke_allocator_arena_create(size_t fixed_capacity);

    /// @brief Statistics for an allocator.
    typedef struct ke_allocator_stats
    {
        size_t total_allocated;  ///< Sum of all requested bytes.
        size_t total_freed;      ///< Sum of all freed bytes.
        size_t active_bytes;     ///< Current bytes in use (allocated - freed).
        uint32_t active_allocs;  ///< Number of allocations that haven't been freed.
    } ke_allocator_stats;

    /**
     * @brief Creates a proxy allocator that tracks statistics of another allocator.
     * @param inner The actual allocator to use.
     * @param name Optional name for the proxy (used in reports).
     * @return A new allocator instance.
     */
    KE_API ke_allocator *ke_allocator_proxy_create(ke_allocator *inner, const char *name);

    /**
     * @brief Retrieves current statistics from a proxy allocator.
     * @param proxy An allocator created with ke_allocator_proxy_create.
     * @param out_stats Pointer to store the results.
     * @return KE_OK or KE_ERROR if the allocator is not a proxy.
     */
    KE_API ke_result ke_allocator_proxy_get_stats(ke_allocator *proxy, ke_allocator_stats *out_stats);

    /**
     * @brief Logs a summary of the proxy allocator and reports leaks if any.
     */
    KE_API void ke_allocator_proxy_report(ke_allocator *proxy, struct ke_logger *logger);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_CONTEXT_ALLOCATOR_H_

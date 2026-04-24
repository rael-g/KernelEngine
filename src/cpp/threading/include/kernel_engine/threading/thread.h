#pragma once

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/threading/threading_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_thread ke_thread;

    /// @brief Function signature for a thread entry point.
    typedef void (*ke_thread_func)(void *user_data);

    /// @brief Construction parameters for ke_thread_create.
    typedef struct ke_thread_desc
    {
        const char    *name;          ///< Thread name, visible in profilers. May be NULL.
        ke_thread_func func;          ///< Entry point. Must not be NULL.
        void          *user_data;     ///< Forwarded unchanged to func.
        uint64_t       affinity_mask; ///< CPU affinity bitmask. 0 = no preference.
    } ke_thread_desc;

    /// @brief Creates and immediately starts a new thread.
    KE_THREADING_API ke_result ke_thread_create(ke_allocator        *alloc,
                                                 const ke_thread_desc *desc,
                                                 ke_thread           **out);

    /// @brief Blocks the caller until the thread finishes.
    KE_THREADING_API void ke_thread_join(ke_thread *t);

    /// @brief Frees the thread handle. Must be called after ke_thread_join.
    KE_THREADING_API void ke_thread_destroy(ke_thread *t, ke_allocator *alloc);

    /// @brief Sets the name of the calling thread (useful for the main thread).
    KE_THREADING_API void ke_thread_set_current_name(const char *name);

#ifdef __cplusplus
}
#endif

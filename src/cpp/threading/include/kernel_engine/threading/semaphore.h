#pragma once

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/threading/threading_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_semaphore ke_semaphore;

    /// @brief Creates a counting semaphore with an initial count.
    KE_THREADING_API ke_result ke_semaphore_create(ke_allocator  *alloc,
                                                    uint32_t       initial,
                                                    ke_semaphore **out);

    /// @brief Increments the semaphore count, unblocking one waiting thread.
    KE_THREADING_API void ke_semaphore_signal(ke_semaphore *s);

    /// @brief Decrements the semaphore count, blocking if it is zero.
    KE_THREADING_API void ke_semaphore_wait(ke_semaphore *s);

    /// @brief Frees the semaphore. No threads must be waiting on it.
    KE_THREADING_API void ke_semaphore_destroy(ke_semaphore *s, ke_allocator *alloc);

#ifdef __cplusplus
}
#endif

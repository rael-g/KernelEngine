#ifndef KERNEL_ENGINE_KERNEL_THREADING_SEMAPHORE_H_
#define KERNEL_ENGINE_KERNEL_THREADING_SEMAPHORE_H_

#include <kernel_engine/kernel/context/allocator.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Counting semaphore abstraction — vtable style.
    typedef struct ke_semaphore
    {
        void *handle;
        void (*destroy)(struct ke_semaphore *self, ke_allocator *alloc);
        void (*signal)(struct ke_semaphore *self);
        void (*wait)(struct ke_semaphore *self);
    } ke_semaphore;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_THREADING_SEMAPHORE_H_

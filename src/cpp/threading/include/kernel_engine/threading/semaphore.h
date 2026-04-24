#pragma once

#include <kernel_engine/kernel/threading/semaphore.h>
#include <kernel_engine/threading/threading_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Creates a counting semaphore with an initial count, filling the ke_semaphore vtable.
    KE_THREADING_API ke_result ke_semaphore_std_create(ke_allocator  *alloc,
                                                        uint32_t       initial,
                                                        ke_semaphore **out);

#ifdef __cplusplus
}
#endif

#pragma once

#include <kernel_engine/kernel/threading/thread.h>
#include <kernel_engine/threading/threading_export.h>

#ifdef __cplusplus
extern "C"
{
#endif

    KE_THREADING_API ke_result ke_thread_std_create(ke_allocator        *alloc,
                                                     const ke_thread_params *desc,
                                                     ke_thread           **out);

#ifdef __cplusplus
}
#endif

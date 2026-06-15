#ifndef KERNEL_ENGINE_KERNEL_CONTEXT_ALLOCATOR_SYS_H_
#define KERNEL_ENGINE_KERNEL_CONTEXT_ALLOCATOR_SYS_H_

#include <kernel_engine/common/export.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_sys_api {
    void* (*malloc)(size_t size);
    void* (*realloc)(void* ptr, size_t size);
    void* (*calloc)(size_t num, size_t size);
    void  (*free)(void* ptr);
} ke_sys_api;

// Internal system API used by the allocator, exposed for testing
KE_API extern ke_sys_api g_ke_sys_api;

#ifdef __cplusplus
}
#endif

#endif

#include <stddef.h>
#include <kernel_engine/task_pool/task_pool.h>
const unsigned long long layout_values[] = {
    sizeof(ke_task_pool),
    offsetof(ke_task_pool, handle),
    offsetof(ke_task_pool, dispatch),
    offsetof(ke_task_pool, dispatch_on_complete),
    offsetof(ke_task_pool, wait),
    offsetof(ke_task_pool, is_completed),
    offsetof(ke_task_pool, get_num_workers),
    sizeof(ke_task_pool_handle),
    offsetof(ke_task_pool_handle, ref),
    offsetof(ke_task_pool_handle, destroy),
    0,
};

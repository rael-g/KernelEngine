#include <stddef.h>
#include <kernel_engine/task_pool/enki/enki_task_pool.h>
#include <kernel_engine/task_pool/enki/task_pool_enki_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_task_pool_enki_params),
    offsetof(ke_task_pool_enki_params, worker_count),
    0,
};

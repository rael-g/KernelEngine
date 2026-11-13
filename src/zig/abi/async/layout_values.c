#include <stddef.h>
#include <kernel_engine/async/async.h>
const unsigned long long layout_values[] = {
    sizeof(ke_async_config),
    offsetof(ke_async_config, worker_count),
    offsetof(ke_async_config, submit_capacity),
    sizeof(ke_async_ctx),
    offsetof(ke_async_ctx, handle),
    offsetof(ke_async_ctx, dep_results),
    offsetof(ke_async_ctx, dep_count),
    offsetof(ke_async_ctx, cancelled),
    sizeof(ke_async),
    offsetof(ke_async, handle),
    offsetof(ke_async, submit),
    offsetof(ke_async, cancel),
    offsetof(ke_async, drain),
    sizeof(ke_async_handle),
    offsetof(ke_async_handle, ref),
    offsetof(ke_async_handle, destroy),
    0,
};

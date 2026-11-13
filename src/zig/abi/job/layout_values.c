#include <stddef.h>
#include <kernel_engine/job/job_system.h>
const unsigned long long layout_values[] = {
    sizeof(ke_job_ctx),
    offsetof(ke_job_ctx, dep_results),
    offsetof(ke_job_ctx, dep_count),
    sizeof(ke_job_system_config),
    offsetof(ke_job_system_config, worker_count),
    sizeof(ke_job_system),
    offsetof(ke_job_system, handle),
    offsetof(ke_job_system, dispatch),
    offsetof(ke_job_system, parallel_for),
    offsetof(ke_job_system, worker_slots),
    offsetof(ke_job_system, drain),
    sizeof(ke_job_system_handle),
    offsetof(ke_job_system_handle, ref),
    offsetof(ke_job_system_handle, destroy),
    0,
};

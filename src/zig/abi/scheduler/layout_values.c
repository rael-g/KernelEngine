#include <stddef.h>
#include <kernel_engine/scheduling/scheduler.h>
#include <kernel_engine/scheduler/scheduler_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_scheduler_executable),
    offsetof(ke_scheduler_executable, run),
    offsetof(ke_scheduler_executable, user),
    sizeof(ke_scheduler),
    offsetof(ke_scheduler, handle),
    offsetof(ke_scheduler, add),
    offsetof(ke_scheduler, tick),
    offsetof(ke_scheduler, shutdown),
    offsetof(ke_scheduler, request_exit),
    offsetof(ke_scheduler, exit_requested),
    offsetof(ke_scheduler, sequence),
    offsetof(ke_scheduler, completed_since),
    offsetof(ke_scheduler, fixed_alpha),
    sizeof(ke_scheduler_handle),
    offsetof(ke_scheduler_handle, ref),
    offsetof(ke_scheduler_handle, destroy),
    0,
};

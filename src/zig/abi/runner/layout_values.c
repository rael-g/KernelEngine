#include <stddef.h>
#include <kernel_engine/runner/runner.h>
const unsigned long long layout_values[] = {
    sizeof(ke_runner),
    offsetof(ke_runner, handle),
    offsetof(ke_runner, run),
    sizeof(ke_runner_handle),
    offsetof(ke_runner_handle, ref),
    offsetof(ke_runner_handle, destroy),
    0,
};

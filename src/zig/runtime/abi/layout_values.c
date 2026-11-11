#include <stddef.h>
#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/runtime_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_runtime_config),
    offsetof(ke_runtime_config, fixed_dt),
    offsetof(ke_runtime_config, fixed_dt_max_accum),
    offsetof(ke_runtime_config, max_systems_per_phase),
    0,
};

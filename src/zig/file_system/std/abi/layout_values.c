#include <stddef.h>
#include <kernel_engine/file_system/std/file_system_std_create.h>
#include <kernel_engine/file_system/std/file_system_std_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_file_system_std_params),
    offsetof(ke_file_system_std_params, root),
    0,
};

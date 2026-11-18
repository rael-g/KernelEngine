#include <stddef.h>
#include <kernel_engine/file_system/file_system.h>
const unsigned long long layout_values[] = {
    sizeof(ke_file_stat),
    offsetof(ke_file_stat, kind),
    offsetof(ke_file_stat, size),
    sizeof(ke_file_system),
    offsetof(ke_file_system, handle),
    offsetof(ke_file_system, open),
    offsetof(ke_file_system, size),
    offsetof(ke_file_system, read_at),
    offsetof(ke_file_system, close),
    offsetof(ke_file_system, stat),
    sizeof(ke_file_system_handle),
    offsetof(ke_file_system_handle, ref),
    offsetof(ke_file_system_handle, destroy),
    0,
};

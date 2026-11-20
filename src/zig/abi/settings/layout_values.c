#include <stddef.h>
#include <kernel_engine/settings/settings.h>
const unsigned long long layout_values[] = {
    sizeof(ke_settings),
    offsetof(ke_settings, handle),
    offsetof(ke_settings, get_bool),
    offsetof(ke_settings, get_int),
    offsetof(ke_settings, get_double),
    offsetof(ke_settings, get_string),
    offsetof(ke_settings, for_each_key),
    offsetof(ke_settings, child),
    offsetof(ke_settings, for_each_child),
    0,
};

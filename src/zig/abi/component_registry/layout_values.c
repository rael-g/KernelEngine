#include <stddef.h>
#include <kernel_engine/framework/component_registry.h>
const unsigned long long layout_values[] = {
    sizeof(ke_component_registry),
    offsetof(ke_component_registry, handle),
    offsetof(ke_component_registry, register_component_fields),
    offsetof(ke_component_registry, get_component_fields),
    offsetof(ke_component_registry, register_component_apply),
    offsetof(ke_component_registry, get_component_apply),
    offsetof(ke_component_registry, register_component_alias),
    offsetof(ke_component_registry, resolve_component),
    sizeof(ke_component_registry_handle),
    offsetof(ke_component_registry_handle, ref),
    offsetof(ke_component_registry_handle, destroy),
    0,
};

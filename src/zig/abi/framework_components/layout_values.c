#include <stddef.h>
#include <kernel_engine/framework/components.h>
const unsigned long long layout_values[] = {
    sizeof(ke_hierarchy_component),
    offsetof(ke_hierarchy_component, parent),
    offsetof(ke_hierarchy_component, first_child),
    offsetof(ke_hierarchy_component, last_child),
    offsetof(ke_hierarchy_component, next_sibling),
    offsetof(ke_hierarchy_component, prev_sibling),
    sizeof(ke_name_component),
    offsetof(ke_name_component, name),
    0,
};

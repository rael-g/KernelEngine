#ifndef KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_
#define KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_

#include <kernel_engine/ecs/ecs.h>

#include <stdalign.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_hierarchy_component
    {
        ke_entity parent;
        ke_entity first_child;
        ke_entity last_child;
        ke_entity next_sibling;
        ke_entity prev_sibling;
    } ke_hierarchy_component;

    typedef struct ke_name_component
    {
        char name[64];
    } ke_name_component;

#define KE_COMPONENT_NAME_HIERARCHY "hierarchy"
#define KE_COMPONENT_NAME_NAME      "name"

/// How `ke_hierarchy_component` is registered: its name, size, alignment, and no field table.
static const ke_component_desc ke_hierarchy_component_desc = { KE_COMPONENT_NAME_HIERARCHY, sizeof(ke_hierarchy_component), alignof(ke_hierarchy_component), NULL, 0 };
/// How `ke_name_component` is registered: its name, size, alignment, and no field table.
static const ke_component_desc ke_name_component_desc = { KE_COMPONENT_NAME_NAME, sizeof(ke_name_component), alignof(ke_name_component), NULL, 0 };

#ifdef __cplusplus
}
#endif

#endif

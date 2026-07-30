#ifndef KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_
#define KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_

#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/components.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_hierarchy_component
    {
        ke_entity parent;
        ke_entity first_child;
        ke_entity next_sibling;
        ke_entity prev_sibling;
    } ke_hierarchy_component;

    typedef struct ke_name_component
    {
        char name[64];
    } ke_name_component;

#define KE_COMPONENT_NAME_HIERARCHY "hierarchy"
#define KE_COMPONENT_NAME_NAME      "name"

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_

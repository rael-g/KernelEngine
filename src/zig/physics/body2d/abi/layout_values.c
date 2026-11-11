#include <stddef.h>
#include <kernel_engine/physics/body2d/body2d_module.h>
#include <kernel_engine/physics/body2d/physics_body2d_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_physics_body2d_module_handle),
    offsetof(ke_physics_body2d_module_handle, ref),
    offsetof(ke_physics_body2d_module_handle, destroy),
    0,
};

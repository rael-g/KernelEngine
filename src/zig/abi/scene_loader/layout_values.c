#include <stddef.h>
#include <kernel_engine/framework/scene_loader.h>
const unsigned long long layout_values[] = {
    sizeof(ke_scene_loader),
    offsetof(ke_scene_loader, handle),
    offsetof(ke_scene_loader, load),
    offsetof(ke_scene_loader, instantiate),
    offsetof(ke_scene_loader, register_script_factory),
    sizeof(ke_scene_loader_handle),
    offsetof(ke_scene_loader_handle, ref),
    offsetof(ke_scene_loader_handle, destroy),
    0,
};

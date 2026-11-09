#include <stddef.h>
#include <kernel_engine/framework/scene_files.h>
const unsigned long long layout_values[] = {
    sizeof(ke_scene_slot_component),
    offsetof(ke_scene_slot_component, path),
    offsetof(ke_scene_slot_component, loaded),
    sizeof(ke_scene_files),
    offsetof(ke_scene_files, handle),
    offsetof(ke_scene_files, instantiate),
    sizeof(ke_scene_files_handle),
    offsetof(ke_scene_files_handle, ref),
    offsetof(ke_scene_files_handle, destroy),
    0,
};

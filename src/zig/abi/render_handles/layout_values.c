#include <stddef.h>
#include <kernel_engine/render/handles.h>
const unsigned long long layout_values[] = {
    sizeof(ke_mesh_handle),
    offsetof(ke_mesh_handle, bits),
    sizeof(ke_texture_handle),
    offsetof(ke_texture_handle, bits),
    sizeof(ke_material_handle),
    offsetof(ke_material_handle, bits),
    sizeof(ke_cubemap_handle),
    offsetof(ke_cubemap_handle, bits),
    sizeof(ke_shadow_map_handle),
    offsetof(ke_shadow_map_handle, bits),
    0,
};

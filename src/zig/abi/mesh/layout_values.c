#include <stddef.h>
#include <kernel_engine/render/mesh.h>
const unsigned long long layout_values[] = {
    sizeof(ke_mesh_vertex),
    offsetof(ke_mesh_vertex, position),
    offsetof(ke_mesh_vertex, normal),
    offsetof(ke_mesh_vertex, uv),
    offsetof(ke_mesh_vertex, tangent),
    0,
};

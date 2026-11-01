#include <stddef.h>
#include <kernel_engine/render/mesh.h>
const unsigned long long layout_values[] = {
    sizeof(ke_vertex),
    offsetof(ke_vertex, x),
    offsetof(ke_vertex, y),
    offsetof(ke_vertex, z),
    offsetof(ke_vertex, nx),
    offsetof(ke_vertex, ny),
    offsetof(ke_vertex, nz),
    offsetof(ke_vertex, u),
    offsetof(ke_vertex, v),
    offsetof(ke_vertex, tx),
    offsetof(ke_vertex, ty),
    offsetof(ke_vertex, tz),
    offsetof(ke_vertex, tw),
    0,
};

#include <stddef.h>
#include <kernel_engine/render/view_space.h>
const unsigned long long layout_values[] = {
    sizeof(ke_view_space),
    offsetof(ke_view_space, handle),
    offsetof(ke_view_space, depth_from_view_z),
    offsetof(ke_view_space, look_to),
    offsetof(ke_view_space, look_at),
    offsetof(ke_view_space, view_from_transform),
    offsetof(ke_view_space, perspective),
    offsetof(ke_view_space, orthographic),
    sizeof(ke_view_space_handle),
    offsetof(ke_view_space_handle, ref),
    offsetof(ke_view_space_handle, destroy),
    0,
};

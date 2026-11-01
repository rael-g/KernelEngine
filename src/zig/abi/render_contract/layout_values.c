#include <stddef.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/render/component_fields.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/service/pass_context.h>
#include <kernel_engine/render/ui/component_fields.h>
const unsigned long long layout_values[] = {
    sizeof(ke_camera_frustum),
    offsetof(ke_camera_frustum, tan_half_fov_y),
    offsetof(ke_camera_frustum, aspect),
    offsetof(ke_camera_frustum, near_plane),
    offsetof(ke_camera_frustum, far_plane),
    sizeof(ke_render_camera),
    offsetof(ke_render_camera, handle),
    offsetof(ke_render_camera, view),
    offsetof(ke_render_camera, view_rotation),
    offsetof(ke_render_camera, projection),
    offsetof(ke_render_camera, perspective_projection),
    offsetof(ke_render_camera, perspective_frustum),
    sizeof(ke_render_camera_handle),
    offsetof(ke_render_camera_handle, ref),
    offsetof(ke_render_camera_handle, destroy),
    sizeof(ke_render_pass_ctx),
    offsetof(ke_render_pass_ctx, handle),
    offsetof(ke_render_pass_ctx, read),
    offsetof(ke_render_pass_ctx, write),
    offsetof(ke_render_pass_ctx, begin_render),
    offsetof(ke_render_pass_ctx, begin_compute),
    offsetof(ke_render_pass_ctx, encoder),
    offsetof(ke_render_pass_ctx, query_ext),
    offsetof(ke_render_pass_ctx, backbuffer_size),
    offsetof(ke_render_pass_ctx, color_source),
    0,
};

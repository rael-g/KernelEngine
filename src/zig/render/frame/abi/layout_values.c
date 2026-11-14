#include <stddef.h>
#include <kernel_engine/render/frame/frame_create.h>
#include <kernel_engine/render/frame/frame_systems_create.h>
#include <kernel_engine/render/frame/render_frame_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_frame_config),
    offsetof(ke_render_frame_config, color_format),
    offsetof(ke_render_frame_config, depth_format),
    offsetof(ke_render_frame_config, clear_color),
    0,
};

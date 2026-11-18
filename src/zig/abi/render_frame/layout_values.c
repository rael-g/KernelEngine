#include <stddef.h>
#include <kernel_engine/render/frame.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_frame),
    offsetof(ke_render_frame, handle),
    offsetof(ke_render_frame, frame_cid),
    offsetof(ke_render_frame, graph),
    offsetof(ke_render_frame, live),
    offsetof(ke_render_frame, color),
    offsetof(ke_render_frame, depth),
    offsetof(ke_render_frame, output),
    offsetof(ke_render_frame, claim_output),
    offsetof(ke_render_frame, publish),
    offsetof(ke_render_frame, find),
    offsetof(ke_render_frame, color_format),
    offsetof(ke_render_frame, depth_format),
    offsetof(ke_render_frame, output_format),
    sizeof(ke_render_frame_handle),
    offsetof(ke_render_frame_handle, ref),
    offsetof(ke_render_frame_handle, destroy),
    0,
};

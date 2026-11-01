#include <stddef.h>
#include <kernel_engine/render/renderdoc_target/gpu_render_target_renderdoc_create.h>
#include <kernel_engine/render/renderdoc_target/gpu_render_target_renderdoc_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_gpu_render_target_renderdoc_params),
    offsetof(ke_gpu_render_target_renderdoc_params, first_frame),
    offsetof(ke_gpu_render_target_renderdoc_params, frame_count),
    0,
};

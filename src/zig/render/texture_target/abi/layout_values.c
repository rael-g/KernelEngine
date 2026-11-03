#include <stddef.h>
#include <kernel_engine/render/texture_target/gpu_render_target_texture_create.h>
#include <kernel_engine/render/texture_target/gpu_render_target_texture_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_gpu_render_target_texture_params),
    offsetof(ke_gpu_render_target_texture_params, texture),
    offsetof(ke_gpu_render_target_texture_params, width),
    offsetof(ke_gpu_render_target_texture_params, height),
    offsetof(ke_gpu_render_target_texture_params, format),
    0,
};

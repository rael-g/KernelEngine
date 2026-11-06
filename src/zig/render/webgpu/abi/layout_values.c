#include <stddef.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_log.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_gpu_device_webgpu_config),
    offsetof(ke_gpu_device_webgpu_config, enable_validation),
    offsetof(ke_gpu_device_webgpu_config, debug_labels),
    sizeof(ke_gpu_render_target_webgpu_window_params),
    offsetof(ke_gpu_render_target_webgpu_window_params, device),
    offsetof(ke_gpu_render_target_webgpu_window_params, window),
    offsetof(ke_gpu_render_target_webgpu_window_params, present_mode),
    offsetof(ke_gpu_render_target_webgpu_window_params, configuration),
    0,
};

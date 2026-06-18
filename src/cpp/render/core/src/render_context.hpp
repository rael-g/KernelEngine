#pragma once

#include <kernel_engine/common/export.h>
#include <kernel_engine/logger/logger.h>
#include <cstdint>

namespace kernel_engine::render
{
class GpuDevice;
}

namespace kernel_engine::render::core
{

class ShaderProviderInterface;

/**
 * @brief Shared state between modular render components.
 * Replaces the need for 'static_cast<CoreRenderer*>(this)'.
 */
struct RenderContext
{
    ke_logger*    logger    = nullptr;
    ShaderProviderInterface* shader_provider = nullptr;
    render::GpuDevice*       gpu = nullptr;

    int32_t view_w = 0;
    int32_t view_h = 0;
    float near_z = 0.1f;
    float far_z = 1000.0f;
    
    float last_view[16]{};
    float last_proj[16]{};
    float camera_pos[4]{0,0,0,0};
};

} // namespace kernel_engine::render::core

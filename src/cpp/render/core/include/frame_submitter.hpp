#pragma once

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include "gpu_types.hpp"
#include <cstdint>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class GeometryManager;
class LightingManager;
class TextureManager;
class ShadowPipeline;

/**
 * @brief Consumes a frame packet and submits draw calls to the HAL.
 * Runs strictly on the render thread.
 */
class FrameSubmitter
{
public:
    static ke_result Submit(RenderContext& ctx,
                           const struct ke_frame_packet& packet,
                           const GeometryManager& geometry,
                           LightingManager& lighting,
                           TextureManager& textures,
                           ShadowPipeline& shadows,
                           GpuProgramHandle program,
                           GpuProgramHandle shadow_program,
                           GpuProgramHandle skybox_program,
                           GpuProgramHandle prepass_program);
};

} // namespace kernel_engine::render::bgfx

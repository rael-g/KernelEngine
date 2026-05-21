#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <kernel_engine/render/core/render_core_export.h>

namespace kernel_engine::render::core
{

struct RenderContext;
class GeometryManager;
class LightingManager;
class TextureManager;
class ShadowPipeline;
class PostProcessPipeline;

/**
 * @brief Responsible for taking a FramePacket and emitting GPU commands via HAL.
 */
class KE_RENDER_CORE_API FrameSubmitter
{
public:
    static ke_result Submit(RenderContext& ctx,
                             const struct ke_frame_packet& packet,
                             const GeometryManager& geometry,
                             LightingManager& lighting,
                             TextureManager& textures,
                             ShadowPipeline& shadows,
                             PostProcessPipeline& post_process,
                             render::GpuProgramHandle main_program,
                             render::GpuProgramHandle shadow_program,
                             render::GpuProgramHandle skybox_program,
                             render::GpuProgramHandle prepass_program);
};

} // namespace kernel_engine::render::core

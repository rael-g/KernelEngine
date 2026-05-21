#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <string>
#include <kernel_engine/render/core/render_core_export.h>

namespace kernel_engine::render::core
{

struct RenderContext;

class KE_RENDER_CORE_API ShaderProviderInterface
{
public:
    virtual ~ShaderProviderInterface() = default;
    virtual const render::GpuMemoryBuffer* LoadShaderBinary(RenderContext& ctx, const std::string& name) = 0;
};

class KE_RENDER_CORE_API FileShaderProvider : public ShaderProviderInterface
{
public:
    explicit FileShaderProvider(const std::string& base_path);
    const render::GpuMemoryBuffer* LoadShaderBinary(RenderContext& ctx, const std::string& name) override;

private:
    std::string base_path_;
};

} // namespace kernel_engine::render::core

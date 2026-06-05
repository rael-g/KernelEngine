#pragma once

#include <kernel_engine/kernel/render/render.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <string>

namespace kernel_engine::render::core
{

struct RenderContext;

class ShaderProviderInterface
{
public:
    virtual ~ShaderProviderInterface() = default;
    virtual const render::GpuMemoryBuffer* LoadShaderBinary(RenderContext& ctx, const std::string& name) = 0;
};

class FileShaderProvider : public ShaderProviderInterface
{
public:
    explicit FileShaderProvider(const std::string& base_path);
    const render::GpuMemoryBuffer* LoadShaderBinary(RenderContext& ctx, const std::string& name) override;

private:
    std::string base_path_;
};

} // namespace kernel_engine::render::core

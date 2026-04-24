#pragma once

#include "gpu_types.hpp"
#include <string>

namespace kernel_engine::render::bgfx
{

struct RenderContext;

/**
 * @brief Agnostic interface for providing shader binaries.
 */
class ShaderProviderInterface
{
public:
    virtual ~ShaderProviderInterface() = default;
    virtual const GpuMemoryBuffer* LoadShaderBinary(RenderContext& ctx, const std::string& name) = 0;
};

/**
 * @brief Default provider that loads shaders from the file system.
 */
class FileShaderProvider : public ShaderProviderInterface
{
public:
    explicit FileShaderProvider(const std::string& base_path);
    const GpuMemoryBuffer* LoadShaderBinary(RenderContext& ctx, const std::string& name) override;

private:
    std::string base_path_;
};

} // namespace kernel_engine::render::bgfx

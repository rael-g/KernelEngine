#pragma once

#include <bgfx/bgfx.h>
#include <string>
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;

/**
 * @brief Interface for providing shader binary data.
 * Isolates the renderer from the file system.
 */
class ShaderProviderInterface
{
public:
    virtual ~ShaderProviderInterface() = default;

    /**
     * @brief Loads a shader binary by name.
     * @param ctx The current render context.
     * @param name The name of the shader (without extension).
     * @return A bgfx memory pointer containing the shader data, or nullptr on failure.
     */
    virtual const ::bgfx::Memory* LoadShaderBinary(RenderContext& ctx, const std::string& name) = 0;
};

/**
 * @brief Implementation that loads shaders from the local file system.
 */
class FileShaderProvider : public ShaderProviderInterface
{
public:
    explicit FileShaderProvider(const std::string& base_path);
    const ::bgfx::Memory* LoadShaderBinary(RenderContext& ctx, const std::string& name) override;

private:
    std::string base_path_;
};

} // namespace kernel_engine::render::bgfx

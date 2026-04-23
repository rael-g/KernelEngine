#include "shader_provider.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
#include <fstream>
#include <vector>

namespace kernel_engine::render::bgfx
{

FileShaderProvider::FileShaderProvider(const std::string& base_path)
    : base_path_(base_path)
{}

const GpuMemoryBuffer* FileShaderProvider::LoadShaderBinary(RenderContext& ctx, const std::string& name)
{
    if (!ctx.gpu) return nullptr;

    std::string full_path = base_path_ + "/" + name + ".bin";
    std::ifstream file(full_path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) return nullptr;

    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    const GpuMemoryBuffer* mem = ctx.gpu->Alloc(static_cast<uint32_t>(size + 1));
    if (mem && file.read(reinterpret_cast<char*>(mem->data), size))
    {
        mem->data[size] = '\0';
        return mem;
    }

    return nullptr;
}

} // namespace kernel_engine::render::bgfx

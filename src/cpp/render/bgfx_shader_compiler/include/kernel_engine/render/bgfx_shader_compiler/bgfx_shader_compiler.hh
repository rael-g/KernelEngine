#pragma once

#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/render/shader_compiler.h>
#include <string>
#include <vector>

namespace kernel_engine::render::shader_compiler
{

class BgfxShaderCompiler
{
  public:
    explicit BgfxShaderCompiler(const ke_shader_compiler_bgfx_params *params);
    ~BgfxShaderCompiler();

    static ke_result OnInitialize();
    static ke_result OnShutdown();

    // Compiler operations
    ke_result CompileShader(const char *file_path, const char *varying_def_path, const char *type, const char *platform,
                            const char *profile, const char **include_paths, size_t include_count);

    ke_shader_compiler *ToApi();

  private:
    ke_shader_compiler compiler_api_{};

    ke_allocator *allocator_ = nullptr;
    ke_logger *logger_ = nullptr;
    std::string shaderc_path_;
};

} // namespace kernel_engine::render::shader_compiler

extern "C"
{
    KE_API ke_result ke_shader_compiler_bgfx_create(const ke_shader_compiler_bgfx_params *params, ke_shader_compiler **out_compiler);
}

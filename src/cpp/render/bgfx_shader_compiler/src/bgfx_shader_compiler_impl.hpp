#pragma once

#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/bgfx_shader_compiler/bgfx_shader_compiler.h>
#include <string>

namespace kernel_engine::render::shader_compiler
{

class BgfxShaderCompiler
{
  public:
    explicit BgfxShaderCompiler(const ke_shader_compiler_bgfx_params *params);
    ~BgfxShaderCompiler();

    static ke_result OnInitialize();
    static ke_result OnShutdown();

    ke_result CompileShader(const char *file_path, const char *varying_def_path, const char *type, const char *platform,
                            const char *profile, const char **include_paths, size_t include_count);

    ke_shader_compiler *ToApi();

    /// Owner-handle destroy: tears down the compiler and frees its allocation.
    static void DestroyApi(ke_shader_compiler *self);

  private:
    ke_shader_compiler compiler_api_{};

    ke_logger *logger_ = nullptr;
    std::string shaderc_path_;
};

} // namespace kernel_engine::render::shader_compiler

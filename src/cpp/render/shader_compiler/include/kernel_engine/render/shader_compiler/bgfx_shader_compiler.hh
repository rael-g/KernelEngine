#pragma once

#include <kernel_engine/core/engine/system.h>
#include <kernel_engine/core/logger/logger.h>
#include <kernel_engine/core/render/shader_compiler.h>
#include <string>
#include <vector>

namespace kernel_engine::render::shader_compiler
{

class BgfxShaderCompiler
{
  public:
    explicit BgfxShaderCompiler(const ke_shader_compiler_bgfx_descriptor *desc);
    ~BgfxShaderCompiler();

    [[nodiscard]] uint64_t Id() const;

    static ke_result OnInitialize();
    static ke_result OnShutdown();
    static ke_result OnUpdate(const ke_frame &frame);

    // Compiler operations
    ke_result CompileShader(const char *file_path, const char *varying_def_path, const char *type, const char *platform,
                            const char *profile, const char **include_paths, size_t include_count);

    ke_system *ToApi();

    [[nodiscard]] ke_shader_compiler *GetCompilerApi()
    {
        return &compiler_api_;
    }

  private:
    ke_system engine_api_{};
    ke_shader_compiler compiler_api_{};

    ke_allocator *allocator_ = nullptr;
    ke_logger *logger_ = nullptr;
    std::string shaderc_path_;
};

} // namespace kernel_engine::render::shader_compiler

extern "C"
{
    KE_API ke_result ke_shader_compiler_bgfx_create(const ke_shader_compiler_bgfx_descriptor *desc, ke_system **out_system);
}

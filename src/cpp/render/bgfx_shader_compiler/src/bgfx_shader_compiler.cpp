#include <kernel_engine/render/bgfx_shader_compiler/bgfx_shader_compiler.hpp>
#include <cstdio>
#include <kernel_engine/kernel/context/allocator.h>
#include <new>
#include <string>
#include <vector>

namespace kernel_engine::render::shader_compiler
{

BgfxShaderCompiler::BgfxShaderCompiler(const ke_shader_compiler_bgfx_params *params)
    : allocator_(params->allocator), logger_(params->logger),
      shaderc_path_((params->shaderc_path != nullptr) ? params->shaderc_path : "")
{
    compiler_api_.handle = this;
    compiler_api_.on_initialize = [](ke_shader_compiler *self) {
        return static_cast<BgfxShaderCompiler *>(self->handle)->OnInitialize();
    };
    compiler_api_.on_shutdown = [](ke_shader_compiler *self) {
        return static_cast<BgfxShaderCompiler *>(self->handle)->OnShutdown();
    };
    compiler_api_.destroy = [](ke_shader_compiler *self) {
        if (!self) return;
        auto *sys = static_cast<BgfxShaderCompiler *>(self->handle);
        auto *alloc = sys->allocator_;
        if (alloc)
        {
            sys->~BgfxShaderCompiler();
            alloc->free(alloc, sys);
        }
    };
    compiler_api_.compile_shader = [](ke_shader_compiler *self, const char *file_path, const char *varying_def_path,
                                      const char *type, const char *platform, const char *profile,
                                      const char **includes, size_t include_count) {
        return static_cast<BgfxShaderCompiler *>(self->handle)
            ->CompileShader(file_path, varying_def_path, type, platform, profile, includes, include_count);
    };
}

BgfxShaderCompiler::~BgfxShaderCompiler()
{
}

ke_shader_compiler *BgfxShaderCompiler::ToApi()
{
    return &compiler_api_;
}

ke_result BgfxShaderCompiler::OnInitialize()
{
    return KE_OK;
}

ke_result BgfxShaderCompiler::OnShutdown()
{
    return KE_OK;
}

ke_result BgfxShaderCompiler::CompileShader(const char *file_path, const char *varying_def_path, const char *type,
                                            const char *platform, const char *profile, const char **includes,
                                            size_t include_count)
{
    if (shaderc_path_.empty())
    {
        ke_log_event ev = {KE_LOG_LEVEL_ERROR, "shader_compiler", "Shaderc path not configured."};
        if (logger_) logger_->log(logger_, &ev);
        return KE_ERROR_NOT_INITIALIZED;
    }

    std::string out_path = file_path;
    size_t last_dot = out_path.find_last_of('.');
    if (last_dot != std::string::npos)
    {
        out_path = out_path.substr(0, last_dot);
    }
    out_path += ".bin";

    std::string cmd = shaderc_path_;
    cmd += " -f " + std::string(file_path);
    cmd += " -o " + out_path;
    cmd += " --varyingdef " + std::string(varying_def_path);
    cmd += " --type " + std::string(type);
    cmd += " --platform " + std::string(platform);
    cmd += " --profile " + std::string(profile);

    for (size_t i = 0; i < include_count; ++i)
    {
        cmd += " -i " + std::string(includes[i]);
    }

    {
        ke_log_event ev = {KE_LOG_LEVEL_INFO, "shader_compiler", cmd.c_str()};
        if (logger_) logger_->log(logger_, &ev);
    }

    int res = system(cmd.c_str());
    if (res != 0)
    {
        ke_log_event ev = {KE_LOG_LEVEL_ERROR, "shader_compiler", "Failed to compile shader."};
        if (logger_) logger_->log(logger_, &ev);
        return KE_ERROR_RENDER;
    }

    {
        ke_log_event ev = {KE_LOG_LEVEL_INFO, "shader_compiler", "Shader compiled successfully."};
        if (logger_) logger_->log(logger_, &ev);
    }
    return KE_OK;
}

} // namespace kernel_engine::render::shader_compiler

extern "C"
{

    ke_result ke_shader_compiler_bgfx_create(const ke_shader_compiler_bgfx_params *params, ke_shader_compiler **out_compiler)
    {
        if (out_compiler == nullptr)
        {
            return KE_ERROR_INVALID_ARGUMENT;
        }
        *out_compiler = NULL;

        if ((params == nullptr) || (params->allocator == nullptr))
        {
            return KE_ERROR_INVALID_ARGUMENT;
        }
        using namespace kernel_engine::render::shader_compiler;
        ke_allocator *alloc = params->allocator;

        void *mem = alloc->alloc(alloc, sizeof(BgfxShaderCompiler), 0);
        if (mem == nullptr)
        {
            return KE_ERROR_OUT_OF_MEMORY;
        }

        BgfxShaderCompiler *sys = new (mem) BgfxShaderCompiler(params);
        *out_compiler = sys->ToApi();
        return KE_OK;
    }
}

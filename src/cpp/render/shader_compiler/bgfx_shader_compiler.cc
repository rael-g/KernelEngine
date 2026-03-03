#include "bgfx_shader_compiler.hh"
#include <cstdio>
#include <cstdlib>
#include <kernel_engine/core/common/hash.h>
#include <kernel_engine/core/context/allocator.h>
#include <new>
#include <string.h>
#include <string>

namespace kernel_engine::domain::render
{

BgfxShaderCompiler::BgfxShaderCompiler(const ke_shader_compiler_bgfx_descriptor *desc)
    : allocator_(desc->allocator), logger_(desc->logger),
      shaderc_path_((desc->shaderc_path != nullptr) ? desc->shaderc_path : "")
{
    compiler_api_.handle = this;
    compiler_api_.destroy = [](ke_shader_compiler *self) { (void)self; };
    compiler_api_.compile_shader = [](ke_shader_compiler *self, const char *file, const char *varying, const char *type,
                                      const char *platform, const char *profile, const char **includes, size_t count) {
        return static_cast<BgfxShaderCompiler *>(self->handle)
            ->CompileShader(file, varying, type, platform, profile, includes, count);
    };

    engine_api_.handle = this;
    engine_api_.numeric_id = ke_hash_string("ke_shader_compiler_bgfx");
    engine_api_.destroy = [](ke_system *self) {
        auto *sys = static_cast<BgfxShaderCompiler *>(self->handle);
        auto *alloc = sys->allocator_;
        sys->~BgfxShaderCompiler();
        if (alloc)
        {
            alloc->free(alloc, sys);
        }
    };
    engine_api_.on_initialize = [](ke_system * /*self*/) {
        return kernel_engine::domain::render::BgfxShaderCompiler::OnInitialize();
    };
    engine_api_.on_shutdown = [](ke_system * /*self*/) {
        return kernel_engine::domain::render::BgfxShaderCompiler::OnShutdown();
    };
    engine_api_.on_update = [](ke_system * /*self*/, const ke_frame *frame) {
        return kernel_engine::domain::render::BgfxShaderCompiler::OnUpdate(*frame);
    };
}

BgfxShaderCompiler::~BgfxShaderCompiler() = default;

uint64_t BgfxShaderCompiler::Id() const
{
    return engine_api_.numeric_id;
}
ke_system *BgfxShaderCompiler::ToApi()
{
    return &engine_api_;
}

ke_result BgfxShaderCompiler::OnInitialize()
{
    return KE_OK;
}
ke_result BgfxShaderCompiler::OnShutdown()
{
    return KE_OK;
}
ke_result BgfxShaderCompiler::OnUpdate(const ke_frame &frame)
{
    (void)frame;
    return KE_OK;
}

ke_result BgfxShaderCompiler::CompileShader(const char *file_path, const char *varying_def_path, const char *type,
                                            const char *platform, const char *profile, const char **include_paths,
                                            size_t include_count)
{
    if ((file_path == nullptr) || (varying_def_path == nullptr) || (type == nullptr) || (platform == nullptr) ||
        (profile == nullptr))
    {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    if (shaderc_path_.empty())
    {
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "shader_compiler", "Shaderc path not configured.");
        }
        return KE_ERROR_NOT_INITIALIZED;
    }

    std::string out_path = file_path;
    size_t const last_dot = out_path.find_last_of('.');
    if (last_dot != std::string::npos)
    {
        out_path = out_path.substr(0, last_dot);
    }
    out_path += ".bin";

    std::string cmd = "\"" + shaderc_path_ + "\"" + " -f " + file_path + " -o " + out_path + " --type " + type +
                      " --platform " + platform + " --profile " + profile + " --varyingdef " + varying_def_path;

    if (include_paths != nullptr)
    {
        for (size_t i = 0; i < include_count; ++i)
        {
            if (include_paths[i] != nullptr)
            {
                cmd += " -i " + std::string(include_paths[i]);
            }
        }
    }

    if (logger_ != nullptr)
    {
        std::string const log_msg = "Compiling shader: " + cmd;
        logger_->log(logger_, KE_LOG_LEVEL_INFO, "shader_compiler", log_msg.c_str());
    }

    int const res = system(cmd.c_str());
    if (res != 0)
    {
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "shader_compiler", "Failed to compile shader.");
        }
        return KE_ERROR;
    }

    if (logger_ != nullptr)
    {
        logger_->log(logger_, KE_LOG_LEVEL_INFO, "shader_compiler", "Shader compiled successfully.");
    }
    return KE_OK;
}

} // namespace kernel_engine::domain::render

extern "C"
{

    ke_result ke_shader_compiler_bgfx_create(const ke_shader_compiler_bgfx_descriptor *desc, ke_system **out_system)
    {
        if ((out_system == nullptr) || (desc == nullptr) || (desc->allocator == nullptr))
        {
            return KE_ERROR_INVALID_ARGUMENT;
        }

        using namespace kernel_engine::domain::render;
        ke_allocator *alloc = desc->allocator;
        void *mem = alloc->alloc(alloc, sizeof(BgfxShaderCompiler), 0);
        if (mem == nullptr)
        {
            return KE_ERROR_OUT_OF_MEMORY;
        }

        BgfxShaderCompiler *sys = new (mem) BgfxShaderCompiler(desc);
        *out_system = sys->ToApi();

        return KE_OK;
    }
}

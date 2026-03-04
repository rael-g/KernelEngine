#include <kernel_engine/render/shader_compiler/bgfx_shader_compiler.hh>
#include <cstdio>
#include <kernel_engine/core/common/hash.h>
#include <kernel_engine/core/context/allocator.h>
#include <new>
#include <string>
#include <vector>

namespace kernel_engine::render::shader_compiler
{

BgfxShaderCompiler::BgfxShaderCompiler(const ke_shader_compiler_bgfx_descriptor *desc)
    : allocator_(desc->allocator), logger_(desc->logger),
      shaderc_path_((desc->shaderc_path != nullptr) ? desc->shaderc_path : "")
{
    compiler_api_.handle = this;
    compiler_api_.destroy = [](ke_shader_compiler *self) { (void)self; };
    compiler_api_.compile_shader = [](ke_shader_compiler *self, const char *file_path, const char *varying_def_path,
                                      const char *type, const char *platform, const char *profile,
                                      const char **includes, size_t include_count) {
        return static_cast<BgfxShaderCompiler *>(self->handle)
            ->CompileShader(file_path, varying_def_path, type, platform, profile, includes, include_count);
    };

    engine_api_.handle = this;
    engine_api_.numeric_id = ke_hash_string("ke_shader_compiler_bgfx");
    engine_api_.destroy = [](ke_system *self) {
        auto *sys = static_cast<BgfxShaderCompiler *>(self->handle);
        auto *alloc = sys->allocator_;
        if (alloc)
        {
            sys->~BgfxShaderCompiler();
            alloc->free(alloc, sys);
        }
    };
    engine_api_.on_initialize = [](ke_system *self) {
        return static_cast<BgfxShaderCompiler *>(self->handle)->OnInitialize();
    };
    engine_api_.on_shutdown = [](ke_system *self) {
        return static_cast<BgfxShaderCompiler *>(self->handle)->OnShutdown();
    };
    engine_api_.on_update = [](ke_system *self, const ke_frame *frame) {
        (void)self;
        (void)frame;
        return KE_OK;
    };
}

BgfxShaderCompiler::~BgfxShaderCompiler()
{
}

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

ke_result BgfxShaderCompiler::CompileShader(const char *file_path, const char *varying_def_path, const char *type,
                                            const char *platform, const char *profile, const char **includes,
                                            size_t include_count)
{
    if (shaderc_path_.empty())
    {
        KE_LOG_ERROR(logger_, "shader_compiler", "Shaderc path not configured.");
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

    KE_LOG_INFO(logger_, "shader_compiler", "Compiling shader: %s", cmd.c_str());

    int res = system(cmd.c_str());
    if (res != 0)
    {
        KE_LOG_ERROR(logger_, "shader_compiler", "Failed to compile shader.");
        return KE_ERROR_RENDER;
    }

    KE_LOG_INFO(logger_, "shader_compiler", "Shader compiled successfully.");
    return KE_OK;
}

} // namespace kernel_engine::render::shader_compiler

extern "C"
{

    ke_result ke_shader_compiler_bgfx_create(const ke_shader_compiler_bgfx_descriptor *desc, ke_system **out_system)
    {
        if (out_system == nullptr)
        {
            return KE_ERROR_INVALID_ARGUMENT;
        }
        *out_system = NULL;

        if ((desc == nullptr) || (desc->allocator == nullptr))
        {
            return KE_ERROR_INVALID_ARGUMENT;
        }
        using namespace kernel_engine::render::shader_compiler;
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

#ifndef KERNEL_ENGINE_RENDER_SHADER_COMPILER_H_
#define KERNEL_ENGINE_RENDER_SHADER_COMPILER_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_SHADER_COMPILER "ke_shader_compiler"

    /// @brief Service for compiling shader source files into engine-ready binaries.
    ///        Vtable contract — concrete implementations live in plugins
    ///        (e.g. `KernelEngine.Render.Bgfx`'s shader compiler).
    typedef struct ke_shader_compiler
    {
        void *handle;
        void (*destroy)(struct ke_shader_compiler *self);

        ke_result (*on_initialize)(struct ke_shader_compiler *self);
        ke_result (*on_shutdown)(struct ke_shader_compiler *self);

        ke_result (*compile_shader)(struct ke_shader_compiler *self, const char *file_path,
                                    const char *varying_def_path, const char *type, const char *platform,
                                    const char *profile, const char **include_paths, size_t include_count);
    } ke_shader_compiler;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_SHADER_COMPILER_H_

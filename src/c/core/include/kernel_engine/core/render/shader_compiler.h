#ifndef KERNEL_ENGINE_CORE_RENDER_SHADER_COMPILER_H_
#define KERNEL_ENGINE_CORE_RENDER_SHADER_COMPILER_H_

#include <kernel_engine/core/common/descriptor.h>
#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/types.h>
#include <kernel_engine/core/engine/system.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_SHADER_COMPILER "ke_shader_compiler"

    /// @brief Service for compiling shader source files into engine-ready binaries.
    typedef struct ke_shader_compiler
    {
        void *handle;
        void (*destroy)(struct ke_shader_compiler *self);

        ke_result (*compile_shader)(struct ke_shader_compiler *self, const char *file_path,
                                    const char *varying_def_path, const char *type, const char *platform,
                                    const char *profile, const char **include_paths, size_t include_count);
    } ke_shader_compiler;

    /// @brief Configuration for the BGFX shader compiler system.
    typedef struct ke_shader_compiler_bgfx_descriptor
    {
        struct ke_allocator *allocator;
        struct ke_logger *logger;
        const char *shaderc_path;
    } ke_shader_compiler_bgfx_descriptor;

#ifndef KE_SHADER_COMPILER_API
#ifdef KE_SHADER_COMPILER_STATIC
#define KE_SHADER_COMPILER_API
#else
#ifdef KE_SHADER_COMPILER_EXPORT
#define KE_SHADER_COMPILER_API KE_HELPER_EXPORT
#else
#define KE_SHADER_COMPILER_API KE_HELPER_IMPORT
#endif
#endif
#endif

    /// @brief Creates a BGFX shader compiler system instance.
    KE_SHADER_COMPILER_API ke_result ke_shader_compiler_bgfx_create(const ke_shader_compiler_bgfx_descriptor *desc,
                                                                    ke_system **out_system);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_CORE_RENDER_SHADER_COMPILER_H_

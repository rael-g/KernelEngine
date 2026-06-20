#ifndef KERNEL_ENGINE_RENDER_BGFX_SHADER_COMPILER_H_
#define KERNEL_ENGINE_RENDER_BGFX_SHADER_COMPILER_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/render/shader_compiler.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_SHADER_COMPILER_BGFX_API
    #ifdef KE_SHADER_COMPILER_BGFX_STATIC
        #define KE_SHADER_COMPILER_BGFX_API
    #else
        #ifdef KE_SHADER_COMPILER_BGFX_EXPORT
            #define KE_SHADER_COMPILER_BGFX_API KE_EXPORT
        #else
            #define KE_SHADER_COMPILER_BGFX_API KE_IMPORT
        #endif
    #endif
#endif

    /// @brief Configuration for the BGFX shader compiler plugin.
    typedef struct ke_shader_compiler_bgfx_params
    {
        struct ke_logger *logger;
        const char *shaderc_path;
    } ke_shader_compiler_bgfx_params;

    /// @brief Creates a BGFX-backed `ke_shader_compiler` instance.
    /// @return Handle whose @c ref is NULL on failure.
    KE_SHADER_COMPILER_BGFX_API ke_shader_compiler_handle ke_shader_compiler_bgfx_create(
        const ke_shader_compiler_bgfx_params *params);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_BGFX_SHADER_COMPILER_H_

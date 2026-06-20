#include <kernel_engine/common/error.h>
#include "../common/example_console_sink.h"
#include <kernel_engine/render/shader_compiler.h>
#include <kernel_engine/render/bgfx_shader_compiler/bgfx_shader_compiler.h>
#include <stdbool.h>
#include <stdio.h>

int main(void)
{
    printf("--- KernelEngine C Shader Compiler Demo ---\n");

    ke_logger_handle logger_h = {0};
    logger_h = ke_logger_create(NULL);
    ke_logger *logger = logger_h.ref;

    logger->add_sink(logger, ke_example_console_sink(KE_LOG_LEVEL_TRACE), NULL);

    ke_shader_compiler_bgfx_params compiler_params = {
        .logger = logger, .shaderc_path = "vcpkg_installed/x64-windows-static-md/tools/bgfx/shaderc.exe"};
    ke_shader_compiler_handle compiler_h = ke_shader_compiler_bgfx_create(&compiler_params);
    ke_shader_compiler *compiler = compiler_h.ref;
    compiler->on_initialize(compiler, NULL);

    ke_log_event ev_start = {KE_LOG_LEVEL_INFO, "app", "Compiling test shader..."};
    logger->log(logger, &ev_start);

    const char* includes[] = { "src/cpp/render/bgfx/shaders" };
    bool ok = compiler->compile_shader(compiler,
        "src/cpp/render/bgfx/shaders/fs_basic.sc",
        "src/cpp/render/bgfx/shaders/varying.def.sc",
        "fragment", "windows", "p30",
        includes, 1, NULL);

    if (ok) {
        ke_log_event ev = {KE_LOG_LEVEL_INFO, "app", "Shader compiled successfully!"};
        logger->log(logger, &ev);
    } else {
        ke_log_event ev = {KE_LOG_LEVEL_ERROR, "app", "Shader compilation failed."};
        logger->log(logger, &ev);
    }

    compiler->on_shutdown(compiler, NULL);
    compiler_h.destroy(compiler_h.ref);
    logger_h.destroy(logger_h.ref);

    printf("--- Demo Complete ---\n");
    return 0;
}

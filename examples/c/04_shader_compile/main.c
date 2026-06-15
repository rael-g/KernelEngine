#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include "../common/example_console_sink.h"
#include <kernel_engine/render/shader_compiler.h>
#include <kernel_engine/render/bgfx_shader_compiler/bgfx_shader_compiler.h>
#include <stdio.h>

int main(void)
{
    printf("--- KernelEngine C Shader Compiler Demo ---\n");

    ke_allocator *alloc = ke_allocator_malloc_create();
    ke_logger *logger = NULL;
    ke_logger_create(alloc, &logger);

    logger->add_sink(logger, ke_example_console_sink(KE_LOG_LEVEL_TRACE));

    ke_shader_compiler_bgfx_params compiler_params = {
        .allocator = alloc, .logger = logger, .shaderc_path = "vcpkg_installed/x64-windows-static-md/tools/bgfx/shaderc.exe"};
    ke_shader_compiler *compiler = NULL;
    ke_shader_compiler_bgfx_create(&compiler_params, &compiler);
    compiler->on_initialize(compiler);

    ke_log_event ev_start = {KE_LOG_LEVEL_INFO, "app", "Compiling test shader..."};
    logger->log(logger, &ev_start);

    const char* includes[] = { "src/cpp/render/bgfx/shaders" };
    ke_result res = compiler->compile_shader(compiler,
        "src/cpp/render/bgfx/shaders/fs_basic.sc",
        "src/cpp/render/bgfx/shaders/varying.def.sc",
        "fragment", "windows", "p30",
        includes, 1);

    if (res == KE_OK) {
        ke_log_event ev = {KE_LOG_LEVEL_INFO, "app", "Shader compiled successfully!"};
        logger->log(logger, &ev);
    } else {
        ke_log_event ev = {KE_LOG_LEVEL_ERROR, "app", "Shader compilation failed."};
        logger->log(logger, &ev);
    }

    compiler->on_shutdown(compiler);
    compiler->destroy(compiler);
    logger->destroy(logger);
    alloc->destroy(alloc);

    printf("--- Demo Complete ---\n");
    return 0;
}

#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/logger/logger.h>
#include <kernel_engine/core/render/shader_compiler.h>
#include <stdio.h>

static void app_console_sink(ke_logger_sink *self, const ke_log_event *ev)
{
    (void)self;
    printf("[%s] %s\n", ev->tag, ev->message);
}

int main(void)
{
    printf("--- KernelEngine C Shader Compiler Demo ---\n");

    ke_allocator *alloc = ke_allocator_malloc_create();
    ke_logger *logger = NULL;
    ke_descriptor core_desc = {.allocator = alloc, .logger = NULL, .message_pipe = NULL};
    ke_logger_create(&core_desc, &logger);

    ke_logger_sink sink = {.handle = NULL, .log = app_console_sink, .destroy = NULL};
    logger->add_sink(logger, sink);

    ke_shader_compiler_bgfx_descriptor compiler_desc = {
        .allocator = alloc, .logger = logger, .shaderc_path = "vcpkg_installed/x64-windows-static-md/tools/bgfx/shaderc.exe"};
    ke_system *compiler_sys = NULL;
    ke_shader_compiler_bgfx_create(&compiler_desc, &compiler_sys);

    ke_shader_compiler *compiler = (ke_shader_compiler *)compiler_sys->handle;

    KE_LOG_INFO(logger, "app", "Compiling test shader...");
    
    const char* includes[] = { "src/cpp/render/bgfx/shaders" };
    ke_result res = compiler->compile_shader(compiler, 
        "src/cpp/render/bgfx/shaders/fs_basic.sc",
        "src/cpp/render/bgfx/shaders/varying.def.sc",
        "fragment", "windows", "p30",
        includes, 1);

    if (res == KE_OK) {
        KE_LOG_INFO(logger, "app", "Shader compiled successfully!");
    } else {
        KE_LOG_ERROR(logger, "app", "Shader compilation failed with result: %d", res);
    }

    compiler_sys->destroy(compiler_sys);
    logger->destroy(logger);
    alloc->destroy(alloc);

    printf("--- Demo Complete ---\n");
    return 0;
}

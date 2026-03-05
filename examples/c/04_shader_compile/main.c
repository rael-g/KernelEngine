#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/render/shader_compiler.h>
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
    ke_shader_compiler *compiler = NULL;
    ke_shader_compiler_bgfx_create(&compiler_desc, &compiler);
    compiler->on_initialize(compiler);

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

    compiler->on_shutdown(compiler);
    compiler->destroy(compiler);
    logger->destroy(logger);
    alloc->destroy(alloc);

    printf("--- Demo Complete ---\n");
    return 0;
}

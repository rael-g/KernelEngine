#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/engine/engine.h>
#include <kernel_engine/core/logger/logger.h>
#include <kernel_engine/core/render/shader_compiler.h>
#include <stdio.h>
#include <stdlib.h>

static void app_console_sink(ke_logger_sink *self, int level, const char *tag, const char *message)
{
    (void)self;
    printf("[%s][%s] %s\n", tag, ke_log_level_to_string(level), message);
}


int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    printf("--- KernelEngine Shader Compiler Demo ---\n");

    ke_allocator *root_alloc = ke_allocator_malloc_create();
    if (!root_alloc)
    {
        return 1;
    }

    ke_descriptor bootstrap_desc = {.allocator = root_alloc, .logger = NULL, .message_pipe = NULL};

    ke_logger *logger = NULL;
    if (ke_logger_create(&bootstrap_desc, &logger) == KE_OK)
    {
        ke_logger_sink sink = {.handle = NULL, .log = app_console_sink, .destroy = NULL};
        logger->add_sink(logger, sink);
    }

    bootstrap_desc.logger = logger;
    ke_engine *engine = NULL;
    ke_engine_create(&bootstrap_desc, &engine);

    ke_system *compiler_sys = NULL;
    ke_shader_compiler_bgfx_descriptor compiler_desc = {
        .allocator = root_alloc,
        .logger = logger,
        .shaderc_path = "C:/vcpkg/packages/bgfx_x64-windows/tools/bgfx/shaderc.exe"};

    if (ke_shader_compiler_bgfx_create(&compiler_desc, &compiler_sys) == KE_OK)
    {
        engine->register_system(engine, compiler_sys);
    }

    engine->initialize(engine);

    ke_shader_compiler *compiler = (ke_shader_compiler *)compiler_sys->handle;
    if (compiler)
    {
        printf("Starting shader compilation...\n");

        const char *vs_path = "src/cpp/render/bgfx/shaders/vs_basic.sc";
        const char *fs_path = "src/cpp/render/bgfx/shaders/fs_basic.sc";
        const char *def_path = "src/cpp/render/bgfx/shaders/varying.def.sc";

        const char *includes[] = {"C:/vcpkg/packages/bgfx_x64-windows/include",
                                  "C:/vcpkg/packages/bgfx_x64-windows/include/bgfx"};

        ke_result res;
        printf("Compiling Vertex Shader...\n");
        res = compiler->compile_shader(compiler, vs_path, def_path, "v", "windows", "s_5_0", includes, 2);
        if (res != KE_OK)
        {
            printf("Failed to compile vertex shader.\n");
        }

        printf("Compiling Fragment Shader...\n");
        res = compiler->compile_shader(compiler, fs_path, def_path, "f", "windows", "s_5_0", includes, 2);
        if (res != KE_OK)
        {
            printf("Failed to compile fragment shader.\n");
        }
    }

    if (engine)
    {
        engine->destroy(engine);
    }
    if (logger)
    {
        logger->destroy(logger);
    }
    root_alloc->destroy(root_alloc);

    printf("--- Demo Complete ---\n");
    return 0;
}

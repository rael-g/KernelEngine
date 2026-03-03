#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/engine/engine.h>
#include <kernel_engine/core/logger/logger.h>
#include <kernel_engine/core/messaging/message_pipe.h>
#include <kernel_engine/core/render/render.h>
#include <kernel_engine/core/window/window.h>
#include <render_plugin.h>
#include <stdio.h>
#include <stdlib.h>
#include <window_plugin.h>

static void app_console_sink(ke_logger_sink *self, int level, const char *tag, const char *message)
{
    (void)self;
    printf("[%s][%s] %s\n", tag, ke_log_level_to_string(level), message);
}


int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    printf("--- KernelEngine Window & Graphics (Full IoC) ---\n");

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
    ke_message_pipe *pipe = NULL;
    ke_message_pipe_create(&bootstrap_desc, &pipe);

    bootstrap_desc.message_pipe = pipe;
    ke_engine *engine = NULL;
    ke_engine_create(&bootstrap_desc, &engine);

    // Create Window
    ke_window_glfw_descriptor win_desc = {.allocator = root_alloc,
                                          .logger = logger,
                                          .message_pipe = pipe,
                                          .width = 800,
                                          .height = 600,
                                          .title = "Window & Graphics (Full IoC)"};
    ke_system *win_sys = NULL;
    ke_window_glfw_create(&win_desc, &win_sys);

    // Manual wiring: Renderer needs the window handle
    ke_window *window = (ke_window *)win_sys->handle;

    // Create Renderer
    ke_render_bgfx_descriptor render_desc = {.allocator = root_alloc,
                                             .logger = logger,
                                             .message_pipe = pipe,
                                             .window = window,
                                             .shader_path = "src/cpp/render/bgfx/shaders"};
    ke_system *render_sys = NULL;
    ke_render_bgfx_create(&render_desc, &render_sys);

    ke_render *render = (ke_render *)render_sys->handle;

    if (engine)
    {
        engine->register_system(engine, win_sys);
        engine->register_system(engine, render_sys);
        engine->initialize(engine);
    }

    float hue = 0.0F;
    while (window && !window->should_close(window))
    {
        hue += 0.005F;
        if (hue > 1.0F)
        {
            hue -= 1.0F;
        }
        if (render)
        {
            render->clear_color(render, hue, 0.2F, 0.4F, 1.0F);
        }
        engine->tick(engine, NULL);
    }

    if (engine)
    {
        engine->destroy(engine);
    }
    if (pipe)
    {
        pipe->destroy(pipe);
    }
    if (logger)
    {
        logger->destroy(logger);
    }
    root_alloc->destroy(root_alloc);

    return 0;
}

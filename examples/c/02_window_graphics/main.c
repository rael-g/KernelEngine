#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/engine/engine.h>
#include <kernel_engine/core/logger/logger.h>
#include <kernel_engine/core/render/render.h>
#include <kernel_engine/core/window/window.h>
#include <stdio.h>

// Forward declarations for plugin creators
typedef struct ke_window_glfw_descriptor {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_message_pipe* message_pipe;
    int width;
    int height;
    const char* title;
} ke_window_glfw_descriptor;

ke_result ke_window_glfw_create(const ke_window_glfw_descriptor* desc, ke_system** out_system);

typedef struct ke_render_bgfx_descriptor {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_message_pipe* message_pipe;
    struct ke_window* window;
    const char* shader_path;
} ke_render_bgfx_descriptor;

ke_result ke_render_bgfx_create(const ke_render_bgfx_descriptor* desc, ke_system** out_system);

static void app_console_sink(ke_logger_sink *self, const ke_log_event *ev)
{
    (void)self;
    printf("[%s] %s\n", ev->tag, ev->message);
}

int main(void)
{
    printf("--- KernelEngine C Window/Graphics Demo ---\n");

    ke_allocator *alloc = ke_allocator_malloc_create();
    ke_logger *logger = NULL;
    ke_descriptor core_desc = {.allocator = alloc, .logger = NULL, .message_pipe = NULL};
    ke_logger_create(&core_desc, &logger);

    ke_logger_sink sink = {.handle = NULL, .log = app_console_sink, .destroy = NULL};
    logger->add_sink(logger, sink);

    ke_descriptor engine_desc = {.allocator = alloc, .logger = logger, .message_pipe = NULL};
    ke_engine *engine = NULL;
    ke_engine_create(&engine_desc, &engine);

    ke_window_glfw_descriptor win_desc = {
        .allocator = alloc, .logger = logger, .message_pipe = NULL, .width = 800, .height = 600, .title = "C Window Demo"};
    ke_system *win_sys = NULL;
    ke_window_glfw_create(&win_desc, &win_sys);
    engine->register_system(engine, win_sys);

    ke_render_bgfx_descriptor render_desc = {.allocator = alloc,
                                             .logger = logger,
                                             .message_pipe = NULL,
                                             .window = (ke_window *)win_sys->handle,
                                             .shader_path = "src/cpp/render/bgfx/shaders"};
    ke_system *render_sys = NULL;
    ke_render_bgfx_create(&render_desc, &render_sys);
    engine->register_system(engine, render_sys);

    engine->initialize(engine);

    ke_window *window = (ke_window *)win_sys->handle;
    ke_render *renderer = (ke_render *)render_sys->handle;

    float hue = 0.0f;
    while (!window->should_close(window))
    {
        hue += 0.005f;
        if (hue > 1.0f) hue -= 1.0f;

        renderer->clear_color(renderer, hue, 0.3f, 0.2f, 1.0f);
        engine->tick(engine, NULL);
    }

    engine->shutdown(engine);
    engine->destroy(engine);
    logger->destroy(logger);
    alloc->destroy(alloc);

    printf("--- Demo Complete ---\n");
    return 0;
}

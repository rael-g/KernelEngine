#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/kernel/ecs/world.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/render.h>
#include <kernel_engine/kernel/window/window.h>
#include <stdio.h>

// Forward declarations for service creators
typedef struct ke_window_glfw_params {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_message_pipe* message_pipe;
    int width;
    int height;
    const char* title;
} ke_window_glfw_params;

ke_result ke_window_glfw_create(const ke_window_glfw_params* params, ke_window** out_window);

typedef struct ke_render_bgfx_params {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_message_pipe* message_pipe;
    struct ke_window* window;
    const char* shader_path;
} ke_render_bgfx_params;

ke_result ke_render_bgfx_create(const ke_render_bgfx_params* params, ke_render** out_render);

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
    ke_logger_create(&logger, NULL);

    ke_logger_sink sink = {.handle = NULL, .log = app_console_sink, .destroy = NULL};
    logger->add_sink(logger, sink, NULL);

    ke_window_glfw_params win_params = {
        .allocator = alloc, .logger = logger, .message_pipe = NULL, .width = 800, .height = 600, .title = "C Window Demo"};
    ke_window *window = NULL;
    ke_window_glfw_create(&win_params, &window);
    window->on_initialize(window, NULL);

    ke_render_bgfx_params render_params = {.allocator = alloc,
                                             .logger = logger,
                                             .message_pipe = NULL,
                                             .window = window,
                                             .shader_path = "src/cpp/render/bgfx/shaders"};
    ke_render *renderer = NULL;
    ke_render_bgfx_create(&render_params, &renderer);
    renderer->on_initialize(renderer, NULL);

    float hue = 0.0f;
    while (!window->should_close(window))
    {
        hue += 0.005f;
        if (hue > 1.0f) hue -= 1.0f;

        renderer->clear_color(renderer, hue, 0.3f, 0.2f, 1.0f);
        window->poll_events(window, NULL);
    }

    renderer->on_shutdown(renderer, NULL);
    renderer->destroy(renderer);
    window->on_shutdown(window, NULL);
    window->destroy(window);
    logger->destroy(logger);
    alloc->destroy(alloc);

    printf("--- Demo Complete ---\n");
    return 0;
}

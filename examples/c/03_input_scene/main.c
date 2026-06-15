#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/ecs/world.h>
#include "../common/example_console_sink.h"
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/window/window.h>
#include <kernel_engine/kernel/input/input.h>
#include <stdio.h>

// Forward declarations for service creators
typedef struct ke_window_glfw_params {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_input* input;
    int width;
    int height;
    const char* title;
} ke_window_glfw_params;

ke_result ke_window_glfw_create(const ke_window_glfw_params* params, ke_window** out_window);

typedef struct ke_render_bgfx_params {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_window* window;
    const char* shader_path;
    uint32_t renderer_type;
} ke_render_bgfx_params;

ke_result ke_render_bgfx_create(const ke_render_bgfx_params* params, ke_render** out_render);

int main(void)
{
    printf("--- KernelEngine C Input Snapshot Demo ---\n");

    ke_allocator *alloc = ke_allocator_malloc_create();
    ke_logger *logger = NULL;
    ke_logger_create(alloc, &logger);

    logger->add_sink(logger, ke_example_console_sink(KE_LOG_LEVEL_TRACE));

    ke_input *input = NULL;
    ke_input_create(alloc, logger, &input);

    ke_window_glfw_params win_params = {
        .allocator = alloc, .logger = logger, .input = input, .width = 800, .height = 600, .title = "C Input Demo"};
    ke_window *window = NULL;
    ke_window_glfw_create(&win_params, &window);
    window->on_initialize(window);

    ke_render_bgfx_params render_params = {
        .allocator = alloc,
        .logger = logger,
        .window = window,
        .shader_path = "src/cpp/render/bgfx/shaders",
        .renderer_type = 0 // default
    };
    ke_render *renderer = NULL;
    ke_render_bgfx_create(&render_params, &renderer);
    renderer->on_initialize(renderer);

    float r = 0.2f;
    while (!window->should_close(window))
    {
        input->update(input);

        // Simple key check via direct (main-thread) API for this C example
        // (In sim thread we would use get_snapshot)
        if (input->is_key_pressed && input->is_key_pressed(input, 32)) // Space
        {
            ke_log_event kev = {KE_LOG_LEVEL_INFO, "app", "Space pressed!"};
            logger->log(logger, &kev);
            r = 0.8f;
        }
        else
        {
            r = 0.2f;
        }

        renderer->clear_color(renderer, r, 0.3f, 0.4f, 1.0f);
        window->poll_events(window);
    }

    renderer->on_shutdown(renderer);
    renderer->destroy(renderer);
    window->on_shutdown(window);
    window->destroy(window);
    input->destroy(input);
    logger->destroy(logger);
    alloc->destroy(alloc);

    printf("--- Demo Complete ---\n");
    return 0;
}

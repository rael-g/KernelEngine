#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/messaging/message_pipe.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/window/window.h>
#include <kernel_engine/kernel/input/input_messages.h>
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

ke_result ke_window_glfw_create(const ke_window_glfw_descriptor* desc, ke_window** out_window);

typedef struct ke_render_bgfx_descriptor {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_message_pipe* message_pipe;
    struct ke_window* window;
    const char* shader_path;
} ke_render_bgfx_descriptor;

ke_result ke_render_bgfx_create(const ke_render_bgfx_descriptor* desc, ke_render** out_render);

static void app_console_sink(ke_logger_sink *self, const ke_log_event *ev)
{
    (void)self;
    printf("[%s] %s\n", ev->tag, ev->message);
}

int main(void)
{
    printf("--- KernelEngine C Input Scene Demo ---\n");

    ke_allocator *alloc = ke_allocator_malloc_create();
    ke_logger *logger = NULL;
    ke_descriptor core_desc = {.allocator = alloc, .logger = NULL, .message_pipe = NULL};
    ke_logger_create(&core_desc, &logger);

    ke_logger_sink sink = {.handle = NULL, .log = app_console_sink, .destroy = NULL};
    logger->add_sink(logger, sink);

    ke_message_pipe *pipe = NULL;
    ke_message_pipe_create(&core_desc, &pipe);

    ke_window_glfw_descriptor win_desc = {
        .allocator = alloc, .logger = logger, .message_pipe = pipe, .width = 800, .height = 600, .title = "C Input Demo"};
    ke_window *window = NULL;
    ke_window_glfw_create(&win_desc, &window);
    window->on_initialize(window);

    ke_render_bgfx_descriptor render_desc = {.allocator = alloc,
                                             .logger = logger,
                                             .message_pipe = pipe,
                                             .window = window,
                                             .shader_path = "src/cpp/render/bgfx/shaders"};
    ke_render *renderer = NULL;
    ke_render_bgfx_create(&render_desc, &renderer);
    renderer->on_initialize(renderer);

    float r = 0.2f;
    while (!window->should_close(window))
    {
        pipe->pump(pipe);

        ke_msg_key_event key_msg;
        if (pipe->try_receive(pipe, KE_MSG_KEY_EVENT, &key_msg, sizeof(key_msg)))
        {
            KE_LOG_INFO(logger, "app", "Key event: %d, action: %d", key_msg.key, key_msg.action);
            r = (key_msg.action == 1) ? 0.8f : 0.2f;
        }

        renderer->clear_color(renderer, r, 0.3f, 0.4f, 1.0f);
        window->poll_events(window);
    }

    renderer->on_shutdown(renderer);
    renderer->destroy(renderer);
    window->on_shutdown(window);
    window->destroy(window);
    pipe->destroy(pipe);
    logger->destroy(logger);
    alloc->destroy(alloc);

    printf("--- Demo Complete ---\n");
    return 0;
}
